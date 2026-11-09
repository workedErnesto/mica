import AppKit
import WebKit
import Combine
import MicaCore

@MainActor
final class DownloadManager: ObservableObject {
    weak var browser: BrowserModel?
    @Published var items: [DownloadItem] = []
    private var history: AnyCancellable?
    init(browser: BrowserModel) {
        self.browser = browser
        if !browser.privateMode {
            history = browser.store.$downloadRecords.sink { [weak self] records in
                guard let self else { return }
                let known = Set(self.items.map(\.id)), kept = Set(records.map(\.id))
                // Another window removed a finished row: drop it here too. Active downloads stay until they end.
                self.items.removeAll { !kept.contains($0.id) && !$0.active }
                self.items.append(contentsOf: records.filter { !known.contains($0.id) }.map { DownloadItem(record: $0, manager: self) })
            }
        }
    }
    func persist(_ item: DownloadItem) {
        guard let browser, !browser.privateMode else { return }
        var records = browser.store.downloadRecords
        if let index = records.firstIndex(where: { $0.id == item.id }) { records[index] = item.record }
        else { records.insert(item.record, at: 0) }
        browser.store.downloadRecords = records
    }
    func add(_ download: WKDownload, tab: Tab) {
        items.insert(DownloadItem(download: download, manager: self, tab: tab), at: 0)
        if let item = items.first { persist(item) }
        browser?.panel = .downloads
    }
    /// Takes a finished, failed or cancelled download off the list. The file itself stays where it was saved.
    func remove(_ item: DownloadItem) {
        guard !item.active else { return }
        items.removeAll { $0.id == item.id }
        guard let browser, !browser.privateMode else { return }
        browser.store.downloadRecords.removeAll { $0.id == item.id }
    }
    func cancelAll() { for item in items where item.state == .running || item.state == .choosing { item.cleanup() } }
}
