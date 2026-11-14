import AppKit
import WebKit
import MicaCore

/// The context menu of a web page, drawn as a mica menu. WebKit still decides what the click was on and builds its
/// items (copy, open link, look up, writing tools); PageView takes them out of WebKit's own menu before it opens, and
/// a chosen row runs the WebKit item, which keeps the context of that click after WebKit's menu is gone.
///
/// mica words the common items itself, so they follow the window's language and letter case; items it does not know
/// keep WebKit's title in the system language. On the page itself (no link, image or selection) mica puts its own
/// navigation and print rows first, and "Search with Google" searches with the engine chosen in mica instead of
/// handing the text to the system's search service.
@MainActor
enum PageMenu {
    enum Item: String {
        case openLink = "WKMenuItemIdentifierOpenLink"
        case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
        case downloadLinkedFile = "WKMenuItemIdentifierDownloadLinkedFile"
        case copyLink = "WKMenuItemIdentifierCopyLink"
        case copyLinkWithHighlight = "WKMenuItemIdentifierCopyLinkWithHighlight"
        case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
        case downloadImage = "WKMenuItemIdentifierDownloadImage"
        case copyImage = "WKMenuItemIdentifierCopyImage"
        case openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
        case downloadMedia = "WKMenuItemIdentifierDownloadMedia"
        case copyMediaLink = "WKMenuItemIdentifierCopyMediaLink"
        case copy = "WKMenuItemIdentifierCopy"
        case cut = "WKMenuItemIdentifierCut"
        case paste = "WKMenuItemIdentifierPaste"
        case lookUp = "WKMenuItemIdentifierLookUp"
        case translate = "WKMenuItemIdentifierTranslate"
        case searchWeb = "WKMenuItemIdentifierSearchWeb"
        case share = "WKMenuItemIdentifierShareMenu"
        case speech = "WKMenuItemIdentifierSpeechMenu"
        case inspect = "WKMenuItemIdentifierInspectElement"
    }

    /// WebKit's navigation items by their tag (WebCore's ContextMenuAction: go back 9, go forward 10, stop 11,
    /// reload 12). "Stop" has no identifier, and the tag names all four the same way.
    static let navigationTags: Set<Int> = [9, 10, 11, 12]

    static func entries(from items: [NSMenuItem], page: PageView, tab: Tab, browser: BrowserModel) -> [MenuEntry] {
        let onPage = items.contains { navigationTags.contains($0.tag) && $0.action != nil }
        var result: [MenuEntry] = []
        if onPage {
            if tab.canBack { result.append(.item(browser.text("назад", "Назад")) { [weak page] in page?.goBack() }) }
            if tab.canForward { result.append(.item(browser.text("вперёд", "Вперёд")) { [weak page] in page?.goForward() }) }
            result.append(.item(browser.text("перезагрузить страницу", "Перезагрузить страницу")) { [weak tab] in tab?.reload() })
            result.append(.divider)
            result.append(.item(browser.text("напечатать страницу…", "Напечатать страницу…")) { [weak tab] in tab?.printPage() })
            result.append(.divider)
        }
        result += convert(onPage ? items.filter { !navigationTags.contains($0.tag) } : items, page: page, browser: browser)
        return result.tidy
    }

    private static func convert(_ items: [NSMenuItem], page: PageView, browser: BrowserModel) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for item in items where !item.isHidden && !item.isAlternate {
            if item.isSeparatorItem { result.append(.divider); continue }
            let kind = item.identifier.flatMap { Item(rawValue: $0.rawValue) }
            if kind == .searchWeb, let query = page.target.selection {
                let engine = browser.prefs.search
                result.append(.item(browser.text("искать в ", "Искать в ") + engine.title(browser.prefs.language)) { [weak browser] in browser?.open(engine.search(query)) })
                continue
            }
            let title = self.title(item, kind, browser)
            if let submenu = item.submenu {
                let children = convert(submenu.items, page: page, browser: browser).tidy
                if !children.isEmpty { result.append(.submenu(title, children)) }
                continue
            }
            guard let action = item.action else { continue }
            // WebKit enables some items later, after it looks at the image (copy subject, visual look up); a mica
            // menu keeps the state of the moment it opened, so an unknown item that is off then is left out.
            let on = enabled(item)
            if kind == nil && !on { continue }
            result.append(.item(title, enabled: on, checked: item.state == .on) {
                NSApp.sendAction(action, to: item.target, from: item)
            })
        }
        return result
    }

    private static func title(_ item: NSMenuItem, _ kind: Item?, _ browser: BrowserModel) -> String {
        let t = browser.text
        switch kind {
        case .openLink: return t("открыть ссылку", "Открыть ссылку")
        case .openLinkInNewWindow: return t("открыть ссылку в новой вкладке", "Открыть ссылку в новой вкладке")
        case .downloadLinkedFile: return t("загрузить файл по ссылке", "Загрузить файл по ссылке")
        case .copyLink: return t("скопировать ссылку", "Скопировать ссылку")
        case .copyLinkWithHighlight: return t("скопировать ссылку с выделением", "Скопировать ссылку с выделением")
        case .openImageInNewWindow: return t("открыть изображение в новой вкладке", "Открыть изображение в новой вкладке")
        case .downloadImage: return t("загрузить изображение", "Загрузить изображение")
        case .copyImage: return t("скопировать изображение", "Скопировать изображение")
        case .openMediaInNewWindow: return t("открыть видео в новой вкладке", "Открыть видео в новой вкладке")
        case .downloadMedia: return t("загрузить видео", "Загрузить видео")
        case .copyMediaLink: return t("скопировать адрес видео", "Скопировать адрес видео")
        case .copy: return t("копировать", "Копировать")
        case .cut: return t("вырезать", "Вырезать")
        case .paste: return t("вставить", "Вставить")
        case .lookUp: return quotedPart(item.title).map { t("найти ", "Найти ") + browser.quoted($0) } ?? item.title
        case .translate: return quotedPart(item.title).map { t("перевести ", "Перевести ") + browser.quoted($0) } ?? item.title
        case .share: return t("поделиться…", "Поделиться…")
        case .speech: return t("речь", "Речь")
        case .inspect: return t("проверить элемент", "Проверить элемент")
        default: return item.title
        }
    }

    /// The selected text WebKit quotes in "Look Up “…”" and "Translate “…”", whatever quote marks the system language uses.
    private static func quotedPart(_ title: String) -> String? {
        guard let open = title.firstIndex(where: { "“«\"„".contains($0) }),
              let close = title.lastIndex(where: { "”»\"“".contains($0) }), open < close else { return nil }
        let part = title[title.index(after: open)..<close]
        return part.isEmpty ? nil : String(part)
    }

    /// WebKit's own items arrive enabled or disabled. Items with no target (speech, writing tools) go to the first
    /// responder, so they ask it, as a system menu would.
    private static func enabled(_ item: NSMenuItem) -> Bool {
        guard item.isEnabled, let action = item.action else { return false }
        if item.target != nil { return true }
        guard let target = NSApp.target(forAction: action, to: nil, from: item) else { return false }
        if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(item) }
        if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(item) }
        return true
    }
}
