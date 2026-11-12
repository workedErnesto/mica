import AppKit
import SwiftUI
import WebKit
import Combine
import CryptoKit
import MicaCore

@MainActor
final class Blocker: ObservableObject {
    unowned let store: Store
    @Published var status = ""
    @Published var count = 0
    @Published var updating = false
    var list: WKContentRuleList?
    private var generation = 0
    let ruleStore: WKContentRuleListStore
    init(store: Store) {
        self.store = store
        let directory = store.root.appendingPathComponent("Rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ruleStore = WKContentRuleListStore(url: directory)
    }
    func rebuild() async {
        generation += 1; let version = generation
        do {
            let cached = store.root.appendingPathComponent("blocklist.txt")
            let bundled = Bundle.main.url(forResource: "blocklist", withExtension: "txt")
            let source = (try? String(contentsOf: cached, encoding: .utf8)) ?? bundled.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let domains = Array(Set(BlockingRules.domains + (try source.map { try BlockingRules.parseDomains($0) } ?? []))).sorted()
            let json = try BlockingRules.json(exceptions: store.preferences.blockingExceptions, domains: domains)
            let fingerprint = SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
            let cacheKey = store.root.appendingPathComponent("blocklist-fingerprint.txt")
            var compiled: WKContentRuleList?
            if (try? String(contentsOf: cacheKey, encoding: .utf8)) == fingerprint { compiled = try? await ruleStore.contentRuleList(forIdentifier: "mica-local-v2") }
            if compiled == nil {
                compiled = try await ruleStore.compileContentRuleList(forIdentifier: "mica-local-v2", encodedContentRuleList: json)
                try fingerprint.write(to: cacheKey, atomically: true, encoding: .utf8)
            }
            guard version == generation else { return }
            list = compiled
            count = domains.count
            status = store.text("локальные правила готовы", "Локальные правила готовы")
            for window in store.windows { for tab in window.model.tabs { apply(tab.webView) } }
        } catch {
            guard version == generation else { return }
            status = error.localizedDescription
            store.issue = store.text("ошибка блокировки: ", "Ошибка блокировки: ") + error.localizedDescription
        }
    }
    func update() async {
        guard !updating else { return }
        updating = true; defer { updating = false }
        do {
            let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 25
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let url = URL(string: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=plain&showintro=0&mimetype=plaintext")!
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url?.host == "pgl.yoyo.org", response.url?.scheme == "https" else { throw CocoaError(.fileReadUnknown) }
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 2_000_000 { throw CocoaError(.fileReadTooLarge) } }
            let domains = try BlockingRules.parseDomains(String(decoding: data, as: UTF8.self))
            guard domains.count >= 100 else { throw CocoaError(.fileReadCorruptFile) }
            let rules = try BlockingRules.json(exceptions: store.preferences.blockingExceptions, domains: Array(Set(domains + BlockingRules.domains)))
            _ = try await ruleStore.compileContentRuleList(forIdentifier: "mica-update-validation", encodedContentRuleList: rules)
            try data.write(to: store.root.appendingPathComponent("blocklist.txt"), options: .atomic)
            await rebuild()
        } catch { status = error.localizedDescription; store.issue = store.text("список не обновлён, предыдущие правила сохранены: ", "Список не обновлён, предыдущие правила сохранены: ") + error.localizedDescription }
    }
    func apply(_ view: WKWebView?) {
        guard let view else { return }
        view.configuration.userContentController.removeAllContentRuleLists()
        if store.preferences.blocking, store.ublock.network == nil, let list { view.configuration.userContentController.add(list) }
        store.ublock.addRules(to: view.configuration.userContentController)
    }
}
