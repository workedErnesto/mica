import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Sendable {
    case duckduckgo = "DuckDuckGo", google = "Google", yandex = "Yandex", kagi = "Kagi", bing = "Bing"
    /// Name shown in the Russian interface; brand spelling is kept.
    public var title: String { self == .yandex ? "Яндекс" : rawValue }
    public func title(_ language: Language) -> String { language == .ru ? title : rawValue }
    public var home: String {
        switch self {
        case .duckduckgo: return "https://duckduckgo.com/"
        case .google: return "https://www.google.com/search"
        case .yandex: return "https://yandex.ru/search/"
        case .kagi: return "https://kagi.com/search"
        case .bing: return "https://www.bing.com/search"
        }
    }
    public func search(_ query: String) -> URL {
        var c = URLComponents(string: home)!
        c.queryItems = [URLQueryItem(name: self == .yandex ? "text" : "q", value: query)]
        return c.url!
    }
    /// True when the URL is this engine's results page for exactly this query.
    public func isSearch(_ url: URL, for query: String) -> Bool { url == search(query) }
}
