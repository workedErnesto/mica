import Foundation

public struct Preferences: Codable, Equatable, Sendable {
    public var layout: TabLayout = .left
    public var language: Language = .preferred()
    /// Name for the start page greeting. Empty or `greetByName == false` keeps the mica wordmark.
    public var userName = ""
    public var greetByName = true
    public static let nameLimit = 32
    public var theme: Theme = .system
    /// Light or dark base of the custom theme.
    public var customBase: Theme = .system
    public var accent = "#6E56CF"
    /// How strongly the custom accent colours the shell, 0 to 0.6.
    public var customTint = 0.3
    public var lowercase = true
    public var frosted = true
    /// Share of the blurred backdrop that shows through the shell tint, 0 opaque to 1 the most see-through.
    public var transparency = 0.55
    public var appIcon: String?
    public var toolbar = ToolbarLayout()
    public var start = StartPage()
    public var search: SearchEngine = .duckduckgo
    public var blocking = true
    public var restore = true
    public var lazyRestore = true
    public var eagerHosts: [String] = []
    public var blockingExceptions: [String] = []
    public var onboardingComplete = false
    public var sidebarCollapsed = false
    public var sidebarWidth = 248.0
    /// Last choice in the clear-data panel.
    public var clearing = ClearChoice()
    public init() {}
    // Missing keys fall back to defaults, so preferences saved by an older build still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        layout = try c.decodeIfPresent(TabLayout.self, forKey: .layout) ?? d.layout
        // Builds before the language setting were Russian only; their users keep Russian.
        language = (try? c.decodeIfPresent(Language.self, forKey: .language)) ?? .ru
        userName = String(((try? c.decodeIfPresent(String.self, forKey: .userName)) ?? d.userName).prefix(Preferences.nameLimit))
        greetByName = (try? c.decodeIfPresent(Bool.self, forKey: .greetByName)) ?? d.greetByName
        theme = (try? c.decodeIfPresent(Theme.self, forKey: .theme)) ?? d.theme
        let base = (try? c.decodeIfPresent(Theme.self, forKey: .customBase)) ?? d.customBase
        customBase = base == .custom ? .system : base
        accent = (try? c.decodeIfPresent(String.self, forKey: .accent)).flatMap { $0 }.flatMap { HexColor.parse($0) == nil ? nil : $0 } ?? d.accent
        customTint = min(0.6, max(0, (try? c.decodeIfPresent(Double.self, forKey: .customTint)) ?? d.customTint))
        lowercase = try c.decodeIfPresent(Bool.self, forKey: .lowercase) ?? d.lowercase
        frosted = try c.decodeIfPresent(Bool.self, forKey: .frosted) ?? d.frosted
        transparency = min(1, max(0, (try? c.decodeIfPresent(Double.self, forKey: .transparency)) ?? d.transparency))
        appIcon = try? c.decodeIfPresent(String.self, forKey: .appIcon)
        toolbar = (try? c.decodeIfPresent(ToolbarLayout.self, forKey: .toolbar)) ?? d.toolbar
        start = (try? c.decodeIfPresent(StartPage.self, forKey: .start)) ?? d.start
        search = (try? c.decodeIfPresent(SearchEngine.self, forKey: .search)) ?? d.search
        blocking = try c.decodeIfPresent(Bool.self, forKey: .blocking) ?? d.blocking
        restore = try c.decodeIfPresent(Bool.self, forKey: .restore) ?? d.restore
        lazyRestore = try c.decodeIfPresent(Bool.self, forKey: .lazyRestore) ?? d.lazyRestore
        eagerHosts = try c.decodeIfPresent([String].self, forKey: .eagerHosts) ?? d.eagerHosts
        blockingExceptions = try c.decodeIfPresent([String].self, forKey: .blockingExceptions) ?? d.blockingExceptions
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? d.onboardingComplete
        sidebarCollapsed = try c.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? d.sidebarCollapsed
        clearing = (try? c.decodeIfPresent(ClearChoice.self, forKey: .clearing)) ?? d.clearing
        sidebarWidth = min(Preferences.sidebarRange.upperBound, max(Preferences.sidebarRange.lowerBound, try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? d.sidebarWidth))
    }
    public static let sidebarRange = 200.0...380.0
}
