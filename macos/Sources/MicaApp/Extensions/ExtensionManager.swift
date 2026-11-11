import AppKit
import WebKit
import CryptoKit
import MicaCore

@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    unowned let store: Store
    let controller: WKWebExtensionController
    @Published var records: [ExtensionRecord] = []
    @Published var errors: [UUID: String] = [:]
    @Published var compatibility: [UUID: String] = [:]
    @Published var catalog: [CatalogEntry] = []
    @Published var catalogStatus = ""
    @Published var busy = false
    @Published var installing: Int?
    /// Chrome Web Store install in progress (extension ID) and its last status line.
    @Published var installingChrome: String?
    @Published var chromeStatus = ""
    @Published var contexts: [UUID: WKWebExtensionContext] = [:]
    /// Button the user clicked last; the action popup opens under it.
    weak var popupAnchor: NSView?
    /// Running extensions in the order they were installed; none for incognito windows.
    func actionable(privateWindow: Bool) -> [ExtensionRecord] { privateWindow ? [] : records.filter { contexts[$0.id] != nil } }
    private var searchTask: Task<Void, Never>?
    var folder: URL { store.root.appendingPathComponent("Extensions", isDirectory: true) }
    init(store: Store) {
        self.store = store
        let configuration: WKWebExtensionController.Configuration = ProcessInfo.processInfo.arguments.contains("--qa") ? .init(identifier: UUID(uuidString: "A3DB54A5-7FCA-4272-81AD-CE40FF1E1353")!) : .default()
        configuration.defaultWebsiteDataStore = store.websiteDataStore
        controller = WKWebExtensionController(configuration: configuration)
        super.init(); controller.delegate = self
    }
    func unsupported(_ ext: WKWebExtension) -> [String] {
        let requested = ext.manifest["permissions"] as? [String] ?? []
        let supported = Set(ext.requestedPermissions.map(\.rawValue))
        return requested.filter { !$0.contains("://") && $0 != "<all_urls>" && !supported.contains($0) }.sorted()
    }
    func validateCompatibility(_ ext: WKWebExtension) throws -> String? {
        let missing = unsupported(ext)
        let essential: Set<String> = ["downloads", "identity", "nativeMessaging", "proxy", "debugger", "bookmarks", "history", "notifications", "webRequestBlocking"]
        let unavailable = missing.filter { essential.contains($0) }
        if !unavailable.isEmpty { throw MicaError.message(store.text("обязательные API недоступны в этом WebKit: ", "Обязательные API недоступны в этом WebKit: ") + unavailable.joined(separator: ", ")) }
        return missing.isEmpty ? nil : store.text("WebKit не предоставляет: ", "WebKit не предоставляет: ") + missing.joined(separator: ", ")
    }
    func persist() { store.save(records, "extensions.json") }
    func restore() async {
        records = (try? Persistence.read([ExtensionRecord].self, at: store.root.appendingPathComponent("extensions.json"))) ?? []
        for record in records where record.enabled { await load(record) }
    }
    func load(_ record: ExtensionRecord) async {
        do {
            let base = folder.appendingPathComponent(record.id.uuidString)
            let digest = try await Task.detached(priority: .utility) { try Self.digest(base) }.value
            guard digest == record.digest else { throw MicaError.message(store.text("файлы изменены. импортируйте расширение заново и проверьте разрешения.", "Файлы изменены. Импортируйте расширение заново и проверьте разрешения.")) }
            let ext = try await WKWebExtension(resourceBaseURL: base)
            guard ext.errors.isEmpty else { throw MicaError.message(ext.errors.map(\.localizedDescription).joined(separator: "\n")) }
            compatibility[record.id] = try validateCompatibility(ext)
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = record.id.uuidString
            context.baseURL = URL(string: "webkit-extension://" + record.id.uuidString.lowercased() + "/")!
            context.hasAccessToPrivateData = false
            context.grantedPermissions = [:]
            context.grantedPermissionMatchPatterns = [:]
            // Host grants and API permissions are separate and persisted explicitly.
            for permission in record.permissions { context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission)) }
            for host in record.hosts { let pattern = try WKWebExtension.MatchPattern(string: host); context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            try controller.load(context)
            contexts[record.id] = context; errors[record.id] = nil
        } catch { errors[record.id] = error.localizedDescription }
    }
    func toggle(_ record: ExtensionRecord) async {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        if let context = contexts[record.id] {
            do { try controller.unload(context); contexts[record.id] = nil; records[index].enabled = false; errors[record.id] = nil }
            catch { errors[record.id] = error.localizedDescription }
        } else { records[index].enabled = true; await load(records[index]); if contexts[record.id] == nil { records[index].enabled = false } }
        persist()
    }
    func remove(_ record: ExtensionRecord) async {
        let result = await ask(title: store.text("удалить расширение?", "Удалить расширение?"), detail: record.name, buttons: [store.text("отмена", "Отмена"), store.text("удалить", "Удалить")])
        guard result == 1 else { return }
        if let context = contexts[record.id] {
            do {
                try controller.unload(context)
                if let data = await controller.dataRecord(ofTypes: WKWebExtensionController.allExtensionDataTypes, for: context) { await controller.removeData(ofTypes: WKWebExtensionController.allExtensionDataTypes, from: [data]) }
            } catch { errors[record.id] = error.localizedDescription; return }
        }
        do { try FileManager.default.removeItem(at: folder.appendingPathComponent(record.id.uuidString)); records.removeAll { $0.id == record.id }; contexts[record.id] = nil; errors[record.id] = nil; persist() }
        catch { errors[record.id] = error.localizedDescription }
    }
    func chooseImport(replacing: ExtensionRecord? = nil) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = store.text("выберите папку с manifest.json или пакет ZIP/XPI. код запускается только после проверки разрешений.", "Выберите папку с manifest.json или пакет ZIP/XPI. Код запускается только после проверки разрешений.")
        panel.begin { [weak self] result in guard result == .OK, let url = panel.url else { return }; Task { await self?.install(url, replacing: replacing) } }
    }
    func install(_ url: URL, replacing: ExtensionRecord? = nil, source: String = "local") async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let staging = store.root.appendingPathComponent("Import-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let package = try await Task.detached(priority: .userInitiated) { try Self.preparePackage(url, staging: staging) }.value
            guard FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path) else { throw MicaError.message(store.text("manifest.json должен находиться в корне пакета", "manifest.json должен находиться в корне пакета")) }
            let manifestSize = try package.appendingPathComponent("manifest.json").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard manifestSize <= 1_000_000 else { throw MicaError.message("manifest.json exceeds 1 MB") }
            let ext = try await WKWebExtension(resourceBaseURL: package)
            guard ext.errors.isEmpty else { throw MicaError.message(ext.errors.map(\.localizedDescription).joined(separator: "\n")) }
            let forbidden = ext.requestedPermissions.filter { ["nativeMessaging", "debugger", "proxy"].contains($0.rawValue) }
            guard forbidden.isEmpty else { throw MicaError.message(store.text("не поддерживаются обязательные разрешения: ", "Не поддерживаются обязательные разрешения: ") + forbidden.map(\.rawValue).joined(separator: ", ")) }
            let warning = try validateCompatibility(ext)
            let name = ext.displayName ?? url.lastPathComponent
            let perms = ext.requestedPermissions.map(\.rawValue).sorted()
            let hosts = ext.requestedPermissionMatchPatterns.map(\.string).sorted()
            let hash = try await Task.detached(priority: .userInitiated) { try Self.digest(package) }.value
            let permissionText = "API: " + (perms.isEmpty ? "—" : perms.joined(separator: ", "))
            let hostText = store.text("сайты: ", "Сайты: ") + (hosts.isEmpty ? "—" : hosts.joined(separator: ", "))
            let sourceText: String
            if source.hasPrefix("cws:") { sourceText = store.text("источник: Chrome Web Store. подпись CRX3 разработчика проверена, ключ соответствует ID расширения. API Chrome доступны в объёме WebKit.", "Источник: Chrome Web Store. Подпись CRX3 разработчика проверена, ключ соответствует ID расширения. API Chrome доступны в объёме WebKit.") }
            else if source.hasPrefix("amo:") { sourceText = store.text("источник: Firefox Add-ons. SHA-256 пакета совпал с ответом каталога.", "Источник: Firefox Add-ons. SHA-256 пакета совпал с ответом каталога.") }
            else { sourceText = store.text("источник: файл с диска. подпись издателя не проверена. SHA-256 фиксирует целостность локальной копии.", "Источник: файл с диска. Подпись издателя не проверена. SHA-256 фиксирует целостность локальной копии.") }
            let note = store.text("окна инкогнито недоступны. совместимость требует проверки.", "Окна инкогнито недоступны. Совместимость требует проверки.")
            let detail = [ext.displayDescription ?? "", sourceText, hash, permissionText, hostText, warning ?? "", note].joined(separator: "\n\n")
            let buttons = [store.text("отмена", "Отмена"), store.text("установить без доступа к сайтам", "Установить без доступа к сайтам"), store.text("установить с указанным доступом", "Установить с указанным доступом")]
            let result = await ask(title: name, detail: detail, buttons: buttons)
            guard result > 0 else { return }
            let record = ExtensionRecord(id: replacing?.id ?? UUID(), name: name, version: ext.version ?? "?", enabled: true, digest: hash, source: source, permissions: perms, hosts: result == 2 ? hosts : [])
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(record.id.uuidString, isDirectory: true)
            if let replacing, let index = records.firstIndex(where: { $0.id == replacing.id }) {
                let backup = store.root.appendingPathComponent("ExtensionRecovery-" + UUID().uuidString, isDirectory: true)
                if let old = contexts[replacing.id] { try controller.unload(old) }
                contexts[replacing.id] = nil
                try FileManager.default.moveItem(at: destination, to: backup)
                do {
                    try FileManager.default.moveItem(at: package, to: destination)
                    records[index] = record
                    await load(record)
                    guard contexts[record.id] != nil else { throw MicaError.message(errors[record.id] ?? "extension load failed") }
                    try? FileManager.default.removeItem(at: backup)
                } catch {
                    if let loaded = contexts[record.id] { try? controller.unload(loaded) }
                    contexts[record.id] = nil
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: backup, to: destination)
                    records[index] = replacing
                    if replacing.enabled { await load(replacing) }
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: package, to: destination)
                records.append(record); await load(record)
                if contexts[record.id] == nil, let index = records.firstIndex(where: { $0.id == record.id }) { records[index].enabled = false }
            }
            persist()
        } catch { store.issue = store.text("расширение не установлено: ", "Расширение не установлено: ") + error.localizedDescription }
    }
    nonisolated static func preparePackage(_ url: URL, staging: URL) throws -> URL {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw MicaError.message("file missing") }
            if isDirectory.boolValue {
                try Self.validateTree(url)
                try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent("package"))
            } else {
                guard ["zip", "xpi"].contains(url.pathExtension.lowercased()), (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 64_000_000 else { throw MicaError.message("a ZIP or XPI up to 64 MB or an unpacked folder is required") }
                // Validate paths, symlinks and expanded sizes BEFORE extraction. CRX and native executables are not supported.
                let listing = try Self.run("/usr/bin/zipinfo", ["-l", url.path])
                let names = try Self.run("/usr/bin/zipinfo", ["-1", url.path]).split(separator: "\n").map(String.init)
                guard names.count <= 10000, names.allSatisfy(PackageSafety.safeEntry), !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw MicaError.message("unsafe archive paths or symlinks") }
                var expanded: Int64 = 0
                for line in listing.split(separator: "\n") {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    if let first = parts.first, first.hasPrefix("-") || first.hasPrefix("d"), parts.count > 3, let size = Int64(parts[3]) { guard size >= 0, size <= 128_000_000 - expanded else { throw MicaError.message("expanded archive exceeds 128 MB") }; expanded += size }
                }
                guard expanded < 128_000_000 else { throw MicaError.message("expanded archive exceeds 128 MB") }
                _ = try Self.run("/usr/bin/ditto", ["-x", "-k", url.path, staging.appendingPathComponent("package").path])
            }
            let package = staging.appendingPathComponent("package")
            try Self.validateTree(package)
        return package
    }
    nonisolated static func validateTree(_ base: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let baseValues = try base.resourceValues(forKeys: keys)
        guard baseValues.isSymbolicLink != true, baseValues.isDirectory == true else { throw MicaError.message("package root must be a real directory") }
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: Array(keys)) else { throw MicaError.message("cannot read package") }
        var count = 0, size = 0
        for case let url as URL in enumerator {
            count += 1; let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { throw MicaError.message("package contains a link or special file") }
            let nextSize = values.fileSize ?? 0
            guard nextSize >= 0, nextSize <= 128_000_000 - size else { throw MicaError.message("package too large") }
            size += nextSize
            guard count <= 10000, size < 128_000_000 else { throw MicaError.message("package too large") }
        }
    }
    nonisolated static func digest(_ base: URL) throws -> String {
        try validateTree(base)
        var hash = SHA256()
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])!
        let files = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
        for url in files where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            hash.update(data: Data(url.path.dropFirst(base.path.count).utf8)); hash.update(data: Data([0]))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var bytes = 0
            while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                bytes += chunk.count
                guard bytes <= 128_000_000 else { throw MicaError.message("file grew beyond package limit") }
                hash.update(data: chunk)
            }
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let output = Pipe(); p.standardOutput = output; p.standardError = FileHandle.nullDevice
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.readData(ofLength: 16384)
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 4_000_000 { p.terminate(); p.waitUntilExit(); throw MicaError.message("archive listing exceeds safety limit") }
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MicaError.message("archive tool failed; try an unpacked directory") }
        return String(decoding: data, as: UTF8.self)
    }
    func search(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { catalog = []; catalogStatus = store.text("введите название для поиска в Firefox Add-ons", "Введите название для поиска в Firefox Add-ons"); return }
        catalogStatus = store.text("поиск в Firefox Add-ons", "Поиск в Firefox Add-ons")
        let language = store.language
        searchTask = Task {
            do {
                var c = URLComponents(string: "https://addons.mozilla.org/api/v5/addons/search/")!
                c.queryItems = [.init(name: "q", value: String(query.prefix(100))), .init(name: "type", value: "extension"), .init(name: "page_size", value: "12")]
                let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 20
                let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(from: c.url!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MicaError.message("Firefox Add-ons is unavailable") }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let results = json["results"] as? [[String: Any]] else { throw MicaError.message("Firefox Add-ons returned an invalid response") }
                func localized(_ field: Any?) -> String { if let value = field as? String { return value }; let values = field as? [String: String] ?? [:]; return (language == .ru ? values["ru"] : nil) ?? values["en-US"] ?? values.values.first ?? "" }
                let entries: [CatalogEntry] = results.compactMap { item in
                    guard let id = item["id"] as? Int, let address = item["url"] as? String, let url = URL(string: address), url.scheme == "https", url.host == "addons.mozilla.org" else { return nil }
                    let version = item["current_version"] as? [String: Any]
                    let file = version?["file"] as? [String: Any]
                    let download = (file?["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host == "addons.mozilla.org" ? $0 : nil }
                    let hash = (file?["hash"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
                    return CatalogEntry(id: id, name: localized(item["name"]), summary: localized(item["summary"]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression), source: url, version: version?["version"] as? String ?? "", permissions: file?["permissions"] as? [String] ?? [], download: download, sha256: hash)
                }
                guard !Task.isCancelled else { return }
                catalog = entries; catalogStatus = entries.isEmpty ? store.text("ничего не найдено", "Ничего не найдено") : store.text("источник: Firefox Add-ons. совместимость каждого расширения не гарантируется.", "Источник: Firefox Add-ons. Совместимость каждого расширения не гарантируется.")
            } catch { if !Task.isCancelled { catalog = []; catalogStatus = store.text("каталог недоступен: ", "Каталог недоступен: ") + error.localizedDescription } }
        }
    }
    func installed(_ entry: CatalogEntry) -> ExtensionRecord? { records.first { $0.source == "amo:\(entry.id)" } ?? records.first { $0.name == entry.name } }
    /// Downloads the AMO-published XPI over HTTPS, checks size and the SHA-256 from the API, then runs the normal import with its permission prompt.
    func installFromCatalog(_ entry: CatalogEntry, replacing: ExtensionRecord? = nil) async {
        guard installing == nil, !busy else { return }
        guard let download = entry.download, let expected = entry.sha256 else { catalogStatus = store.text("у этого расширения нет пакета для прямой установки", "У этого расширения нет пакета для прямой установки"); return }
        installing = entry.id; defer { installing = nil }
        let temporary = store.root.appendingPathComponent("AMO-" + UUID().uuidString + ".xpi")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.httpCookieStorage = nil
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: download)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https" else { throw MicaError.message("Firefox Add-ons download failed") }
            guard data.count <= 64_000_000 else { throw MicaError.message("package exceeds 64 MB") }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw MicaError.message(store.text("контрольная сумма пакета не совпала с AMO, установка отменена", "Контрольная сумма пакета не совпала с AMO, установка отменена")) }
            try data.write(to: temporary, options: .atomic)
            await install(temporary, replacing: replacing, source: "amo:\(entry.id)")
        } catch { catalogStatus = store.text("не удалось установить: ", "Не удалось установить: ") + error.localizedDescription }
    }
    /// Downloads the CRX the store serves to Chrome, checks the developer signature and the ID, then runs the regular
    /// import with its permission prompt. Accepts a store address or a bare extension ID.
    func installFromChromeStore(_ input: String) async {
        guard let id = ChromeStore.extensionID(from: input) else { chromeStatus = store.text("нужна ссылка на страницу расширения в Chrome Web Store или его ID из 32 букв", "Нужна ссылка на страницу расширения в Chrome Web Store или его ID из 32 букв"); return }
        guard installingChrome == nil, installing == nil, !busy else { return }
        installingChrome = id; defer { installingChrome = nil }
        chromeStatus = store.text("загрузка и проверка подписи…", "Загрузка и проверка подписи…")
        let temporary = store.root.appendingPathComponent("CWS-" + UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 40; config.httpCookieStorage = nil
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: ChromeStore.downloadURL(id: id))
            guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" else { throw MicaError.message("Chrome Web Store download failed") }
            guard http.statusCode == 200, !data.isEmpty else { throw MicaError.message(store.text("магазин не отдал пакет: расширение не найдено, снято с публикации или недоступно для загрузки", "Магазин не отдал пакет: расширение не найдено, снято с публикации или недоступно для загрузки")) }
            guard data.count <= 64_000_000 else { throw MicaError.message("package exceeds 64 MB") }
            let package = try CRXPackage(data)
            try package.verify(expectedID: id)
            try package.archive.write(to: temporary, options: .atomic)
            chromeStatus = ""
            await install(temporary, replacing: records.first { $0.source == "cws:" + id }, source: "cws:" + id)
        } catch { chromeStatus = store.text("не удалось установить: ", "Не удалось установить: ") + error.localizedDescription }
    }
    func action(_ record: ExtensionRecord, tab: Tab?) {
        guard let context = contexts[record.id] else { return }
        if let tab { context.userGesturePerformed(in: tab) }
        context.performAction(for: tab)
    }
    func revokeHosts(_ record: ExtensionRecord) async {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        if let context = contexts[record.id] { for pattern in context.currentPermissionMatchPatterns { context.setPermissionStatus(.deniedExplicitly, for: pattern) } }
        records[index].hosts = []; persist()
    }
    func allowCurrentSite(_ record: ExtensionRecord, tab: Tab?) async {
        guard let url = tab?.url, let origin = Origin.string(url), tab?.owner?.privateMode == false, let context = contexts[record.id], let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let answer = await ask(title: record.name, detail: store.text("разрешить чтение и изменение страниц на ", "Разрешить чтение и изменение страниц на ") + origin + "?", buttons: [store.text("отмена", "Отмена"), store.text("разрешить", "Разрешить")])
        guard answer == 1, let scheme = url.scheme, let host = url.host else { return }
        do {
            let value = "\(scheme)://\(host)/*"
            let pattern = try WKWebExtension.MatchPattern(string: value)
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
            records[index].hosts = Array(Set(records[index].hosts + [value])).sorted(); persist()
        } catch { errors[record.id] = error.localizedDescription }
    }
    func options(_ record: ExtensionRecord) { if let context = contexts[record.id], let url = context.optionsPageURL { store.active?.open(url) } }
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] { store.windows.map(\.model).filter { !$0.privateMode } }
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { store.active?.privateMode == false ? store.active : nil }
    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        let browser = configuration.window as? BrowserModel ?? store.windows.first(where: { !$0.model.privateMode })?.model
        guard let browser, !browser.privateMode else { completionHandler(nil, MicaError.message("no nonprivate window")); return }
        let tab = browser.add(saved: SavedTab(url: configuration.url, pinned: configuration.shouldBePinned), activate: configuration.shouldBeActive)
        completionHandler(tab, nil)
    }
    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionWindow)?, Error?) -> Void) {
        guard !configuration.shouldBePrivate else { completionHandler(nil, MicaError.message("private extensions are disabled")); return }
        guard configuration.tabs.isEmpty else { completionHandler(nil, MicaError.message("moving existing tabs between windows is not supported")); return }
        let window = store.newWindow()
        for (i, url) in configuration.tabURLs.enumerated() { if i == 0 { window.selected?.load(url) } else { window.open(url) } }
        completionHandler(window, nil)
    }
    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { if let url = context.optionsPageURL { store.active?.open(url); completionHandler(nil) } else { completionHandler(MicaError.message("no options page")) } }
    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let popover = action.popupPopover else { completionHandler(MicaError.message("popup unavailable")); return }
        popover.behavior = .transient
        // Under the clicked button when it is still on screen in the key window; otherwise near the top right of the window.
        if let anchor = popupAnchor, let window = anchor.window, window.isKeyWindow || window == store.active?.controller?.window {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let view = store.active?.controller?.window?.contentView {
            popover.show(relativeTo: NSRect(x: view.bounds.maxX - 60, y: view.bounds.maxY - Chrome.bar, width: 24, height: 24), of: view, preferredEdge: .minY)
        } else { completionHandler(MicaError.message("popup unavailable")); return }
        popupAnchor = nil
        completionHandler(nil)
    }
    /// Icon, badge, title or enabled state changed: redraw the extension buttons.
    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) { objectWillChange.send() }
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        Task {
            let safe = permissions.filter { !["nativeMessaging", "proxy", "debugger"].contains($0.rawValue) }
            let answer = await ask(title: context.webExtension.displayName ?? "mica", detail: safe.map(\.rawValue).sorted().joined(separator: ", "), buttons: [store.text("запретить", "Запретить"), store.text("разрешить", "Разрешить")])
            completionHandler(answer == 1 ? safe : [], .distantFuture)
            if answer == 1, let index = records.firstIndex(where: { $0.id.uuidString == context.uniqueIdentifier }) { records[index].permissions = Array(Set(records[index].permissions + safe.map(\.rawValue))).sorted(); persist() }
        }
    }
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        Task {
            let answer = await ask(title: context.webExtension.displayName ?? "mica", detail: patterns.map(\.string).sorted().joined(separator: "\n"), buttons: [store.text("запретить", "Запретить"), store.text("разрешить", "Разрешить")])
            completionHandler(answer == 1 ? patterns : [], .distantFuture)
            if answer == 1, let index = records.firstIndex(where: { $0.id.uuidString == context.uniqueIdentifier }) { records[index].hosts = Array(Set(records[index].hosts + patterns.map(\.string))).sorted(); persist() }
        }
    }
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        Task {
            let answer = await ask(title: context.webExtension.displayName ?? "mica", detail: urls.map { Origin.string($0) ?? $0.absoluteString }.sorted().joined(separator: "\n"), buttons: [store.text("запретить", "Запретить"), store.text("один раз", "Один раз")])
            completionHandler(answer == 1 ? urls : [], Date().addingTimeInterval(300))
        }
    }
}
