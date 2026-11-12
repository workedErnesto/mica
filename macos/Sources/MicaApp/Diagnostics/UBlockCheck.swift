import AppKit
import WebKit
import MicaCore

/// QA only (`--qa --ublock-check`): opens a YouTube video in a regular tab once uBlock Origin's filters are ready and
/// records whether the player shows an ad and whether the video itself plays. The cookie answers YouTube's consent
/// page with "reject all", as a regular visitor from the EU would. Writes `ublock-check.json` in the QA profile.
@MainActor
enum UBlockCheck {
    static func run(store: Store) async {
        var report: [String: Any] = ["engine": store.ublock.active]
        func save() { try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: store.root.appendingPathComponent("ublock-check.json"), options: .atomic) }
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        while store.ublock.active && store.ublock.stats == nil && ProcessInfo.processInfo.systemUptime < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        report["stats"] = store.ublock.summary
        guard let browser = store.active else { report["error"] = "no window"; return save() }
        let cookie = HTTPCookie(properties: [.domain: ".youtube.com", .path: "/", .name: "SOCS", .value: "CAI", .secure: "TRUE", .expires: Date().addingTimeInterval(86_400)])!
        await browser.dataStore.httpCookieStore.setCookie(cookie)
        let video = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ublock-check=") }.map { String($0.dropFirst("--ublock-check=".count)) } ?? "L4SAAIUcMus"
        browser.open(URL(string: "https://www.youtube.com/watch?v=" + video)!)
        guard let tab = browser.selected else { report["error"] = "no tab"; return save() }
        let probe = """
        const p = document.getElementById('movie_player'); const ip = window.ytInitialPlayerResponse;
        return { title: document.title, initialAds: !!(ip && (ip.adPlacements || ip.playerAds || ip.adSlots)), adShowing: !!document.querySelector('#movie_player.ad-showing'),
          time: p && p.getCurrentTime ? p.getCurrentTime() : null, scripts: tab };
        """
        var samples: [[String: Any]] = []
        for seconds in [8, 16, 24] {
            try? await Task.sleep(for: .seconds(8))
            // Autoplay waits for a click in mica; the check starts the video the way the play button does.
            _ = try? await tab.webView?.callAsyncJavaScript("document.getElementById('movie_player')?.playVideo?.()", contentWorld: .page)
            let value = try? await tab.webView?.callAsyncJavaScript(probe, arguments: ["tab": tab.webView?.configuration.userContentController.userScripts.filter(UBlockEngine.owns).count ?? 0], contentWorld: .page)
            var sample = value as? [String: Any] ?? ["error": "no result"]; sample["t"] = seconds
            samples.append(sample)
        }
        report["samples"] = samples
        save()
    }
}
