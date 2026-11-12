import AppKit
import WebKit
import Combine
import MicaCore

@MainActor
final class DownloadItem: NSObject, ObservableObject, Identifiable, WKDownloadDelegate {
    let id: UUID
    weak var manager: DownloadManager?
    weak var tab: Tab?
    @Published var name = ""
    @Published var state: DownloadState = .choosing { didSet { scheduleSave(); if saving { manager?.objectWillChange.send() } } }
    @Published var fraction = 0.0
    @Published var bytes: Int64 = 0
    @Published var total: Int64 = 0
    @Published var failure: String?
    /// When the download started; nil only for an old record whose file is gone.
    @Published var date: Date?
    /// True for a short while after the file lands, while the row shows a drawn checkmark instead of the kind icon.
    @Published var justFinished = false
    var destination: URL?
    var staging: URL?
    var resumeData: Data?
    var download: WKDownload?
    var request: URLRequest?
    var observation: NSKeyValueObservation?
    var scoped = false
    var bookmark: Data?
    private var saveScheduled = false
    var record: DownloadRecord {
        DownloadRecord(id: id, name: name, state: state.rawValue, destination: destination, bookmark: bookmark,
            source: source, bytes: bytes, total: total, date: date)
    }
    /// Address to copy or download again: plain GET over the web only, never form posts or local schemes.
    var source: URL? { request?.httpMethod == "GET" && ["http", "https"].contains(request?.url?.scheme ?? "") ? request?.url : nil }
    var kind: DownloadKind { DownloadKind.of(name) }
    /// Final size of a finished file; while running, `total` is what the server announced.
    var size: Int64 { max(total, bytes) }
    private func scheduleSave() {
        guard !saveScheduled else { return }; saveScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }; self.saveScheduled = false; self.manager?.persist(self)
        }
    }
    init(record: DownloadRecord, manager: DownloadManager) {
        id = record.id; self.manager = manager
        super.init()
        name = record.name; destination = record.destination; bookmark = record.bookmark
        state = record.state == "complete" ? .complete : .cancelled
        bytes = record.bytes; total = record.total; fraction = state == .complete ? 1 : 0; date = record.date
        if let source = record.source { request = URLRequest(url: source) }
        if date == nil || (state == .complete && size == 0) { backfill() }
    }
    /// Records written before downloads kept a date: take the date and size from the file once and save them.
    private func backfill() {
        accessDestination(); defer { releaseScope() }
        guard let destination, let values = try? destination.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]) else { return }
        if date == nil { date = values.creationDate }
        if size == 0, let length = values.fileSize { total = Int64(length) }
        // The manager is still applying the record list that created this item; save after it finishes.
        Task { @MainActor [weak self] in if let self { self.manager?.persist(self) } }
    }
    private func accessDestination() {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                destination = resolved
            }
        }
        scoped = destination?.startAccessingSecurityScopedResource() ?? false
    }
    /// A page mica writes itself (PageSaver) rather than a WKDownload: the row shows it while the file is made.
    var saving = false
    /// Makes the saved page again into the same file; the retry button calls it.
    var saveAgain: (() -> Void)?
    var work: Task<Void, Never>?
    init(saving name: String, destination: URL, tab: Tab, manager: DownloadManager) {
        id = UUID(); self.manager = manager; self.tab = tab; date = Date(); saving = true
        super.init()
        self.name = name; self.destination = destination; state = .running; fraction = 0.05
    }
    func savingFinished() {
        guard state == .running else { return }
        bookmark = try? destination?.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let length = (try? destination?.resourceValues(forKeys: [.fileSizeKey]))??.fileSize ?? 0
        bytes = Int64(length); total = bytes; failure = nil
        state = .complete; fraction = 1
        celebrate()
    }
    func savingFailed(_ error: Error) {
        guard state == .running else { return }
        failure = error.localizedDescription; state = .failed
    }
    init(download: WKDownload, manager: DownloadManager, tab: Tab) {
        id = UUID(); self.manager = manager; self.tab = tab; date = Date()
        super.init(); attach(download)
    }
    func attach(_ download: WKDownload) {
        self.download = download; request = download.originalRequest ?? request; download.delegate = self
        observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted, bytes = progress.completedUnitCount, total = progress.totalUnitCount
            Task { @MainActor [weak self] in self?.fraction = fraction; self?.bytes = bytes; self?.total = total }
        }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let browser = manager?.browser else { completionHandler(nil); return }
        name = DownloadSafety.filename(suggestedFilename)
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.message = browser.text("сохранить загрузку", "Сохранить загрузку")
        let result: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { self?.state = .cancelled; completionHandler(nil); return }
            self.destination = url; self.name = url.lastPathComponent; self.scoped = url.startAccessingSecurityScopedResource()
            let folder = browser.store.root.appendingPathComponent("Downloads", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stage = folder.appendingPathComponent(UUID().uuidString + ".part")
                self.staging = stage; self.state = .running
                completionHandler(stage)
            } catch { self.failure = error.localizedDescription; self.state = .failed; completionHandler(nil); self.releaseScope() }
        }
        if let window = browser.controller?.window { panel.beginSheetModal(for: window, completionHandler: result) } else { result(panel.runModal()) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        observation = nil; self.download = nil
        Task {
            guard let destination, let staging, let browser = manager?.browser else { return }
            do {
                var values: [String: Any] = ["LSQuarantineAgentName": "mica", "LSQuarantineType": "LSQuarantineTypeWebDownload"]
                if let url = request?.url { values["LSQuarantineDataURL"] = url }
                try (staging as NSURL).setResourceValue(values, forKey: .quarantinePropertiesKey)
                if FileManager.default.fileExists(atPath: destination.path) {
                    let choice = await ask(title: browser.text("заменить существующий файл?", "Заменить существующий файл?"), detail: destination.lastPathComponent, buttons: [browser.text("отмена", "Отмена"), browser.text("заменить", "Заменить")], window: browser.controller?.window, destructive: true)
                    guard choice == 1 else { state = .cancelled; try? FileManager.default.removeItem(at: staging); releaseScope(); return }
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                } else { try FileManager.default.moveItem(at: staging, to: destination) }
                bookmark = try? destination.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                if total < bytes { total = bytes }
                state = .complete; fraction = 1; resumeData = nil
                celebrate()
            } catch { failure = error.localizedDescription; state = .failed }
            releaseScope()
        }
    }
    /// Checkmark for `MotionTokens.doneHold` seconds, then the kind icon.
    private var hold: Task<Void, Never>?
    private func celebrate() {
        hold?.cancel(); justFinished = true
        hold = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MotionTokens.doneHold))
            guard !Task.isCancelled else { return }
            self?.justFinished = false
        }
    }
    /// Waiting for a place to save or receiving bytes: such a row cannot be removed from the list.
    var active: Bool { state == .choosing || state == .running }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        observation = nil; self.download = nil
        if state != .cancelled { state = .failed; failure = error.localizedDescription }
        self.resumeData = resumeData; releaseScope(); manager?.persist(self)
    }
    func cancel() {
        state = .cancelled; observation = nil; work?.cancel(); work = nil
        download?.cancel { [weak self] data in self?.resumeData = data; self?.download = nil; self?.releaseScope() }
    }
    func retry() {
        if let saveAgain { saveAgain(); return }
        guard let browser = manager?.browser else { return }
        tab = tab ?? browser.selected
        tab?.makeWebView()
        guard let web = tab?.webView else { return }
        failure = nil; state = .running
        if let data = resumeData {
            scoped = destination?.startAccessingSecurityScopedResource() ?? false
            web.resumeDownload(fromResumeData: data) { [weak self] in self?.attach($0) }
        } else if let request { state = .choosing; web.startDownload(using: request) { [weak self] in self?.attach($0) } }
        else { state = .failed }
    }
    func reveal() { accessDestination(); defer { releaseScope() }; if let destination, state == .complete { NSWorkspace.shared.activateFileViewerSelecting([destination]) } }
    func open() {
        accessDestination()
        guard let destination, state == .complete, let browser = manager?.browser else { return }
        Task {
            let answer = await ask(title: browser.text("открыть загруженный файл?", "Открыть загруженный файл?"), detail: destination.lastPathComponent, buttons: [browser.text("отмена", "Отмена"), browser.text("открыть", "Открыть")], window: browser.controller?.window)
            if answer == 1 { NSWorkspace.shared.open(destination) }; releaseScope()
        }
    }
    func releaseScope() { if scoped, let destination { destination.stopAccessingSecurityScopedResource(); scoped = false } }
    func cleanup() { cancel(); releaseScope(); manager?.persist(self) }
}
