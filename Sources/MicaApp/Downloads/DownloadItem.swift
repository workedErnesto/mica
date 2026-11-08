import AppKit
import WebKit
import Combine
import MicaCore

@MainActor
final class DownloadItem: NSObject, ObservableObject, Identifiable, WKDownloadDelegate {
    let id = UUID()
    weak var manager: DownloadManager?
    weak var tab: Tab?
    @Published var name = ""
    @Published var state: DownloadState = .choosing
    @Published var fraction = 0.0
    @Published var bytes: Int64 = 0
    @Published var total: Int64 = 0
    @Published var failure: String?
    var destination: URL?
    var staging: URL?
    var resumeData: Data?
    var download: WKDownload?
    var request: URLRequest?
    var observation: NSKeyValueObservation?
    var scoped = false
    init(download: WKDownload, manager: DownloadManager, tab: Tab) {
        self.manager = manager; self.tab = tab
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
                    let choice = await ask(title: browser.text("заменить существующий файл?", "Заменить существующий файл?"), detail: destination.lastPathComponent, buttons: [browser.text("отмена", "Отмена"), browser.text("заменить", "Заменить")], window: browser.controller?.window)
                    guard choice == 1 else { state = .cancelled; try? FileManager.default.removeItem(at: staging); releaseScope(); return }
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                } else { try FileManager.default.moveItem(at: staging, to: destination) }
                state = .complete; fraction = 1; resumeData = nil
            } catch { failure = error.localizedDescription; state = .failed }
            releaseScope()
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        observation = nil; self.download = nil
        if state != .cancelled { state = .failed; failure = error.localizedDescription }
        self.resumeData = resumeData; releaseScope()
    }
    func cancel() {
        state = .cancelled; observation = nil
        download?.cancel { [weak self] data in self?.resumeData = data; self?.download = nil; self?.releaseScope() }
    }
    func retry() {
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
    func reveal() { if let destination, state == .complete { NSWorkspace.shared.activateFileViewerSelecting([destination]) } }
    func open() {
        guard let destination, state == .complete, let browser = manager?.browser else { return }
        Task {
            let answer = await ask(title: browser.text("открыть загруженный файл?", "Открыть загруженный файл?"), detail: destination.lastPathComponent, buttons: [browser.text("отмена", "Отмена"), browser.text("открыть", "Открыть")], window: browser.controller?.window)
            if answer == 1 { NSWorkspace.shared.open(destination) }
        }
    }
    func releaseScope() { if scoped, let destination { destination.stopAccessingSecurityScopedResource(); scoped = false } }
    func cleanup() { cancel(); releaseScope(); if let staging { try? FileManager.default.removeItem(at: staging) }; resumeData = nil }
}
