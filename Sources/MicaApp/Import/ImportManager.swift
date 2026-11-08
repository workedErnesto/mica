import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MicaCore

/// Moves history and bookmarks from browsers on this Mac into mica.
/// Files are read from copies; the source browser is never written to.
@MainActor
final class ImportManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reading
        case done(Summary)
        case failed(String)
    }
    struct Summary: Equatable {
        var source: String
        var history = 0
        var bookmarks = 0
        var problems: [String] = []
    }

    @Published private(set) var profiles: [ImportProfile] = []
    @Published private(set) var discovered = false
    @Published var selection: ImportProfile.ID?
    @Published var kinds: Set<ImportKind> = Set(ImportKind.allCases)
    @Published private(set) var phase: Phase = .idle
    private unowned let store: Store
    private var authorizedFolder: URL?
    private var authorizedProfileIDs: Set<ImportProfile.ID> = []

    init(store: Store) { self.store = store }

    var selected: ImportProfile? { profiles.first { $0.id == selection } }
    /// Safari's own files are readable only with Full Disk Access.
    var safariLocked: Bool {
        guard let safari = selected, safari.browser.family == .safari else { return false }
        return !FileManager.default.isReadableFile(atPath: safari.path.appendingPathComponent("Bookmarks.plist").path)
    }

    func discover() {
        Task {
            let found = await Task.detached(priority: .userInitiated) { ImportDiscovery.profiles() }.value
            profiles = found
            if selection == nil || !found.contains(where: { $0.id == selection }) {
                selection = found.first(where: { $0.browser.family != .safari }).map(\.id) ?? found.first?.id
            }
            discovered = true
        }
    }

    func title(_ profile: ImportProfile) -> String { profile.browser.displayName(store.preferences.language) }


    func run() {
        guard let profile = selected, phase != .reading else { return }
        let wanted = kinds.intersection(profile.browser.kinds)
        guard !wanted.isEmpty else { return }
        phase = .reading
        Task {
            let read = await Task.detached(priority: .userInitiated) { ImportReader.read(profile, kinds: wanted) }.value
            var summary = apply(read.bundle, source: title(profile))
            summary.problems = read.failures.sorted { $0.key.rawValue < $1.key.rawValue }.map { describe($0.value, kind: $0.key) }
            withMotion(Motion.quick) { phase = .done(summary) }
        }
    }

    /// Safari export (ZIP or unpacked folder), or a bookmarks HTML file from any browser.
    func chooseExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .html, .json, .folder]
        panel.message = store.text("выберите архив экспорта Safari, его папку или HTML-файл с закладками", "Выберите архив экспорта Safari, его папку или HTML-файл с закладками")
        panel.prompt = store.text("перенести", "Перенести")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        phase = .reading
        Task {
            let result: Result<ImportBundle, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    guard url.pathExtension.lowercased() == "zip" else { return .success(try SafariReader.export(at: url)) }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mica-export-" + UUID().uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: folder) }
                    let unzip = Process()
                    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    unzip.arguments = ["-x", "-k", url.path, folder.path]
                    try unzip.run(); unzip.waitUntilExit()
                    guard unzip.terminationStatus == 0 else { throw ImportError.unreadable(url.lastPathComponent) }
                    return .success(try SafariReader.export(at: folder))
                } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let bundle):
                let summary = apply(bundle, source: url.lastPathComponent)
                withMotion(Motion.quick) { phase = .done(summary) }
            case .failure:
                withMotion(Motion.quick) { phase = .failed(store.text("в файле нет закладок или истории в известном формате", "В файле нет закладок или истории в известном формате")) }
            }
        }
    }

    func chooseProfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = realHome().appendingPathComponent("Library/Application Support", isDirectory: true)
        panel.message = store.text("выберите папку профиля браузера или папку с его профилями", "Выберите папку профиля браузера или папку с его профилями")
        panel.prompt = store.text("выбрать", "Выбрать")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        let found = ImportDiscovery.profiles(authorizedFolder: folder)
        guard !found.isEmpty else {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            phase = .failed(store.text("профили в этой папке не найдены", "Профили в этой папке не найдены"))
            return
        }
        if let authorizedFolder { authorizedFolder.stopAccessingSecurityScopedResource() }
        authorizedFolder = scoped ? folder : nil
        profiles.removeAll { authorizedProfileIDs.contains($0.id) }
        authorizedProfileIDs = Set(found.map(\.id))
        for profile in found where !profiles.contains(where: { $0.id == profile.id }) { profiles.append(profile) }
        selection = found[0].id
        reset()
    }

    func reset() { withMotion(Motion.quick) { phase = .idle } }

    private func apply(_ bundle: ImportBundle, source: String) -> Summary {
        var summary = Summary(source: source)
        if !bundle.history.isEmpty {
            let merged = ImportMerge.history(store.history, adding: bundle.history)
            store.history = merged.merged; summary.history = merged.added
        }
        if !bundle.bookmarks.isEmpty {
            let merged = ImportMerge.bookmarks(store.bookmarks, adding: bundle.bookmarks)
            store.bookmarks = merged.merged; summary.bookmarks = merged.added
        }
        return summary
    }

    private func describe(_ error: ImportError, kind: ImportKind) -> String {
        let what: String
        switch kind {
        case .history: what = store.text("история", "История")
        case .bookmarks: what = store.text("закладки", "Закладки")
        }
        switch error {
        case .noAccess: return what + store.text(": нет доступа к файлу", ": нет доступа к файлу")
        case .unreadable: return what + store.text(": файл не прочитан, возможно, браузер сменил формат", ": файл не прочитан, возможно, браузер сменил формат")
        }
    }
}
