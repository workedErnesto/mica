import AppKit
import WebKit
import Combine
import MicaCore

@MainActor
final class DownloadManager: ObservableObject {
    weak var browser: BrowserModel?
    @Published var items: [DownloadItem] = []
    init(browser: BrowserModel) { self.browser = browser }
    func add(_ download: WKDownload, tab: Tab) {
        items.insert(DownloadItem(download: download, manager: self, tab: tab), at: 0)
        browser?.panel = .downloads
    }
    func cancelAll() { for item in items { item.cleanup() }; items.removeAll() }
}
