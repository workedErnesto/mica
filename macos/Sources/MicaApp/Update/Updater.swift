import AppKit
import CryptoKit
import Darwin
import MicaCore

@MainActor
final class Updater {
    private unowned let store: Store
    private var schedule: Task<Void, Never>?
    private var checking = false
    private var didOfferInstallation = false
    private let lastCheckKey = "lastReleaseCheck"
    private let interval = UpdatePolicy.checkInterval
    private var current: AppVersion? { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) }

    init(store: Store) { self.store = store }

    func start() {
        guard !ProcessInfo.processInfo.arguments.contains("--qa") else { return }
        schedule = Task { [weak self] in
            guard let self else { return }
            if !self.didOfferInstallation {
                self.didOfferInstallation = true
                await self.offerDiskInstallation()
            }
            while !Task.isCancelled {
                let last = UserDefaults.standard.object(forKey: self.lastCheckKey) as? Date
                let delay = UpdatePolicy.delaySinceLastCheck(last)
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard !Task.isCancelled else { break }
                if self.store.preferences.updateChecks { await self.check() }
                else { try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000)) }
            }
        }
    }

    func enableChecks(_ enabled: Bool) {
        store.preferences.updateChecks = enabled
        if enabled {
            store.preferences.skippedVersion = nil
            UserDefaults.standard.removeObject(forKey: lastCheckKey)
            schedule?.cancel()
            start()
        }
    }

    private func check() async {
        guard !checking, let current, store.preferences.updateChecks else { return }
        checking = true
        defer { checking = false }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        do {
            var request = URLRequest(url: UpdatePolicy.latestURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("mica", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard UpdatePolicy.offer(release, current: current, preferences: store.preferences), let version = release.version else { return }
            let answer = await ask(title: store.text("доступна mica ", "Доступна mica ") + version.description,
                detail: store.text("образ будет проверен по SHA-256 и открыт в Finder. установку вы завершите сами", "Образ будет проверен по SHA-256 и открыт в Finder. Установку вы завершите сами"),
                buttons: [store.text("установить", "Установить"), store.text("позже", "Позже"), store.text("не предлагать эту версию", "Не предлагать эту версию"), store.text("не предлагать никогда", "Не предлагать никогда")])
            switch answer {
            case 0: await download(release)
            case 2: store.preferences.skippedVersion = version.description
            case 3: store.preferences.updateChecks = false
            default: break
            }
        } catch { /* Automatic checks retry the next day. */ }
    }

    private func download(_ release: Release) async {
        guard let disk = release.disk, let checksum = release.checksum else { return }
        do {
            // Release assets must originate on GitHub; URLSession follows GitHub's HTTPS asset redirect.
            guard [disk.url, checksum.url].allSatisfy({ $0.scheme == "https" && $0.host == "github.com" }),
                  disk.name == URL(fileURLWithPath: disk.name).lastPathComponent else { throw UpdateError.invalid }
            let (sumData, sumResponse) = try await URLSession.shared.data(from: checksum.url)
            guard (sumResponse as? HTTPURLResponse)?.statusCode == 200, sumData.count < 4096,
                  let expected = String(data: sumData, encoding: .utf8).flatMap(UpdatePolicy.parseChecksum) else { throw UpdateError.invalid }
            let (temporary, response) = try await URLSession.shared.download(from: disk.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.invalid }
            let actual = try await Task.detached(priority: .utility) { try Self.sha256(temporary) }.value
            guard actual == expected else { throw UpdateError.checksum }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = disk.name
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.message = store.text("сохраните проверенный образ mica", "Сохраните проверенный образ mica")
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            try data.write(to: destination, options: .atomic)
            try Self.ensureQuarantine(destination)
            guard NSWorkspace.shared.open(destination) else { throw UpdateError.open }
        } catch {
            let reason: String
            switch error {
            case UpdateError.checksum: reason = store.text("контрольная сумма не совпала. образ не открыт", "Контрольная сумма не совпала. Образ не открыт")
            case UpdateError.quarantine: reason = store.text("не удалось включить проверку Gatekeeper. образ не открыт", "Не удалось включить проверку Gatekeeper. Образ не открыт")
            default: reason = store.text("не удалось скачать или открыть образ. попробуйте позже", "Не удалось скачать или открыть образ. Попробуйте позже")
            }
            _ = await ask(title: store.text("обновление не установлено", "Обновление не установлено"), detail: reason, buttons: [store.text("понятно", "Понятно")])
        }
    }

    nonisolated private static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func ensureQuarantine(_ url: URL) throws {
        if getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 { return }
        let quarantine = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));mica;"
        guard setxattr(url.path, "com.apple.quarantine", quarantine, quarantine.utf8.count, 0, 0) == 0 else { throw UpdateError.quarantine }
    }

    private func offerDiskInstallation() async {
        guard InstallState.runsFromDiskImage(Bundle.main.bundleURL.path), let current else { return }
        let target = URL(fileURLWithPath: "/Applications/mica.app", isDirectory: true)
        let installed = Bundle(url: target)?.infoDictionary?["CFBundleShortVersionString"] as? String
        let state = InstallState.compare(running: current, installed: installed.flatMap(AppVersion.init))
        let title: String
        let detail: String
        switch state {
        case .notInstalled:
            title = store.text("установить mica в «Программы»?", "Установить mica в «Программы»?")
            detail = store.text("выберите папку «Программы» для установки", "Выберите папку «Программы» для установки")
        case .older(let version):
            title = store.text("обновить mica в «Программах»?", "Обновить mica в «Программах»?")
            detail = store.text("установлена версия ", "Установлена версия ") + version.description + store.text(", на образе версия ", ", на образе версия ") + current.description
        case .same, .newer: return
        }
        let answer = await ask(title: title, detail: detail, buttons: [store.text("позже", "Позже"), store.text("продолжить", "Продолжить")])
        guard answer == 1 else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = store.text("выберите папку «Программы»", "Выберите папку «Программы»")
        panel.prompt = store.text("выбрать", "Выбрать")
        guard panel.runModal() == .OK, let folder = panel.url, folder.standardizedFileURL.path == "/Applications" else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let fm = FileManager.default
            let target = folder.appendingPathComponent("mica.app")
            let staged = folder.appendingPathComponent(".mica-install-\(UUID().uuidString).app")
            let backup = folder.appendingPathComponent(".mica-backup-\(UUID().uuidString).app")
            defer { try? fm.removeItem(at: staged) }
            if fm.fileExists(atPath: target.path) {
                guard let bundle = Bundle(url: target), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                      let raw = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                      let version = AppVersion(raw), version < current else { throw UpdateError.invalid }
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: staged)
            try Self.ensureQuarantine(staged)
            if fm.fileExists(atPath: target.path) {
                try fm.moveItem(at: target, to: backup)
                do { try fm.moveItem(at: staged, to: target) }
                catch { try? fm.moveItem(at: backup, to: target); throw error }
                try? fm.removeItem(at: backup)
            } else { try fm.moveItem(at: staged, to: target) }
            NSWorkspace.shared.activateFileViewerSelecting([target])
            _ = await ask(title: store.text("mica установлена", "mica установлена"), detail: store.text("откройте mica из папки «Программы»", "Откройте mica из папки «Программы»"), buttons: [store.text("понятно", "Понятно")])
        } catch {
            _ = await ask(title: store.text("не удалось установить mica", "Не удалось установить mica"), detail: store.text("проверьте доступ к папке «Программы» и установленную версию", "Проверьте доступ к папке «Программы» и установленную версию"), buttons: [store.text("понятно", "Понятно")])
        }
    }
    private enum UpdateError: Error { case invalid, checksum, quarantine, open }
}
