import Foundation

/// What a profile changes: the start page, the window arrangement, theme and colours, the greeting name, and the language
/// and letter case of the interface text.
/// Passwords, cookies, history, bookmarks, downloads and extensions are shared by every profile.
/// The keys are those of `Preferences`, so preferences saved before profiles decode straight into the standard profile.
public struct ProfileLook: Codable, Equatable, Sendable {
    public var layout: TabLayout
    public var theme: Theme
    public var customBase: Theme
    public var accent: String
    public var customTint: Double
    public var frosted: Bool
    public var transparency: Double
    public var userName: String
    public var greetByName: Bool
    public var toolbar: ToolbarLayout
    public var start: StartPage
    public var sidebarCollapsed: Bool
    public var sidebarWidth: Double
    /// Interface language and letter case of this profile's windows. `nil` only in profiles saved before they had their own,
    /// which keep following the application-wide setting until the store fills them in.
    public var language: Language?
    public var lowercase: Bool?

    public init() { self.init(Preferences()) }
    public init(_ p: Preferences) {
        layout = p.layout; theme = p.theme; customBase = p.customBase; accent = p.accent; customTint = p.customTint
        frosted = p.frosted; transparency = p.transparency; userName = p.userName; greetByName = p.greetByName
        toolbar = p.toolbar; start = p.start; sidebarCollapsed = p.sidebarCollapsed; sidebarWidth = p.sidebarWidth
        language = p.language; lowercase = p.lowercase
    }
    /// Fills a missing language or case from `source`.
    public mutating func adopt(_ source: ProfileLook) {
        if language == nil { language = source.language }
        if lowercase == nil { lowercase = source.lowercase }
    }
    /// The application-wide preferences with this profile's part laid over them.
    public func applied(to base: Preferences) -> Preferences {
        var p = base
        p.layout = layout; p.theme = theme; p.customBase = customBase; p.accent = accent; p.customTint = customTint
        p.frosted = frosted; p.transparency = transparency; p.userName = userName; p.greetByName = greetByName
        p.toolbar = toolbar; p.start = start; p.sidebarCollapsed = sidebarCollapsed; p.sidebarWidth = sidebarWidth
        p.language = language ?? base.language; p.lowercase = lowercase ?? base.lowercase
        return p
    }
    /// Decoding goes through `Preferences`, which already repairs and clamps every one of these values.
    /// A language or case the file does not have stays `nil` instead of taking the `Preferences` default.
    public init(from decoder: Decoder) throws {
        self.init(try Preferences(from: decoder))
        let c = try decoder.container(keyedBy: Keys.self)
        language = try? c.decodeIfPresent(Language.self, forKey: .language)
        lowercase = try? c.decodeIfPresent(Bool.self, forKey: .lowercase)
    }
    private enum Keys: String, CodingKey { case layout, theme, customBase, accent, customTint, frosted, transparency, userName, greetByName, toolbar, start, sidebarCollapsed, sidebarWidth, language, lowercase }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(layout, forKey: .layout); try c.encode(theme, forKey: .theme); try c.encode(customBase, forKey: .customBase)
        try c.encode(accent, forKey: .accent); try c.encode(customTint, forKey: .customTint); try c.encode(frosted, forKey: .frosted)
        try c.encode(transparency, forKey: .transparency); try c.encode(userName, forKey: .userName); try c.encode(greetByName, forKey: .greetByName)
        try c.encode(toolbar, forKey: .toolbar); try c.encode(start, forKey: .start); try c.encode(sidebarCollapsed, forKey: .sidebarCollapsed)
        try c.encode(sidebarWidth, forKey: .sidebarWidth); try c.encodeIfPresent(language, forKey: .language); try c.encodeIfPresent(lowercase, forKey: .lowercase)
    }
}

/// Where a profile chosen in the profile menu opens. Switching a window replaces its pinned tabs with the profile's,
/// so the safe default asks first.
public enum ProfileOpening: String, Codable, CaseIterable, Sendable { case ask, here, newWindow }

/// Colour of the profile glyph on its background. `auto` picks white or ink by contrast.
public enum ProfileGlyph: String, Codable, CaseIterable, Sendable { case auto, light, dark }

/// A named look for browser windows. Every window belongs to one profile; the standard profile always exists,
/// can be renamed and get another icon, but cannot be removed.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public static let standardID = UUID(uuidString: "6D1CA000-0000-4000-8000-000000000001")!
    public static let nameLimit = 32
    public var id: UUID
    /// Empty only for the standard profile, which then shows its localized default name.
    public var name: String
    public var icon: String
    public var background: String
    public var glyph: ProfileGlyph = .auto
    public var look: ProfileLook
    /// Pinned tabs a new window of this profile opens with. Updated from the profile's windows as they change.
    public var pinned: [SavedTab]
    public var isStandard: Bool { id == Profile.standardID }

    public init(id: UUID = UUID(), name: String, icon: String, background: String, glyph: ProfileGlyph = .auto, look: ProfileLook = ProfileLook(), pinned: [SavedTab] = []) {
        self.id = id; self.name = name; self.icon = icon; self.background = background; self.glyph = glyph; self.look = look; self.pinned = pinned
    }
    public static func standard(look: ProfileLook = ProfileLook()) -> Profile {
        Profile(id: standardID, name: "", icon: ProfileCatalog.standardIcon, background: ProfileCatalog.standardBackground, look: look)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = Profiles.name((try? c.decodeIfPresent(String.self, forKey: .name)) ?? "")
        let icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? ""
        self.icon = ProfileCatalog.icons.contains(icon) ? icon : ProfileCatalog.standardIcon
        let background = ((try? c.decodeIfPresent(String.self, forKey: .background)) ?? "").uppercased()
        self.background = HexColor.parse(background) == nil ? ProfileCatalog.standardBackground : background
        glyph = (try? c.decodeIfPresent(ProfileGlyph.self, forKey: .glyph)) ?? .auto
        look = (try? c.decodeIfPresent(ProfileLook.self, forKey: .look)) ?? ProfileLook()
        pinned = ((try? c.decodeIfPresent([SavedTab].self, forKey: .pinned)) ?? []).filter { $0.pinned && $0.url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && AddressParser.navigable($0) } == true }
    }
}

public enum Profiles {
    public static let limit = 24
    /// Spaces and line breaks around the name are dropped; the name keeps its case and is cut at `Profile.nameLimit`.
    public static func name(_ input: String) -> String {
        String(input.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(Profile.nameLimit))
    }
    /// The standard profile first, each id once, other profiles in their order. A list without the standard one gets it back.
    public static func normalized(_ list: [Profile], fallback: ProfileLook = ProfileLook()) -> [Profile] {
        var seen = Set<UUID>()
        var result = list.filter { seen.insert($0.id).inserted }
        var standard = result.first { $0.isStandard } ?? .standard(look: fallback)
        result.removeAll { $0.isStandard }
        // Profiles saved before they had their own language and case take the application-wide ones.
        for index in result.indices { result[index].look.adopt(fallback) }
        standard.look.adopt(fallback)
        standard.pinned = standard.pinned.filter(\.pinned)
        return Array(([standard] + result).prefix(limit))
    }
    /// The profile with this id, or the standard one when it was removed or never existed.
    public static func resolve(_ id: UUID?, in list: [Profile]) -> Profile {
        list.first { $0.id == id } ?? list.first { $0.isStandard } ?? .standard()
    }
    /// A new profile takes the first icon and the first background no other profile uses yet. It keeps the arrangement
    /// and colours of the look it starts from, but not that profile's own sites and hidden sites on the start page.
    public static func next(after list: [Profile], name: String, look source: ProfileLook) -> Profile {
        var look = source
        look.start.shortcuts = []; look.start.hiddenHosts = []
        let icons = Set(list.map(\.icon)), backgrounds = Set(list.map(\.background))
        let icon = ProfileCatalog.icons.first { !icons.contains($0) } ?? ProfileCatalog.icons[list.count % ProfileCatalog.icons.count]
        let background = ProfileCatalog.backgrounds.first { !backgrounds.contains($0) } ?? ProfileCatalog.backgrounds[list.count % ProfileCatalog.backgrounds.count]
        return Profile(name: Profiles.name(name), icon: icon, background: background, look: look)
    }
    /// The standard profile cannot be removed.
    public static func removing(_ id: UUID, from list: [Profile]) -> [Profile] {
        id == Profile.standardID ? list : list.filter { $0.id != id }
    }
    /// Visits recorded before profiles existed belong to the standard profile.
    public static func owner(of visit: Visit) -> UUID { visit.profile ?? Profile.standardID }
    /// Default name of the standard profile until the user renames it; another profile is never left without a name.
    public static func displayName(_ profile: Profile, lowercase: Bool, language: Language) -> String {
        guard profile.name.isEmpty else { return profile.name }
        return profile.isStandard ? Copy.text("обычный", "Обычный", lowercase: lowercase, language: language) : Copy.text("профиль", "Профиль", lowercase: lowercase, language: language)
    }
    /// Glyph colour on the profile background. `auto` keeps white while it has the 3:1 contrast WCAG asks of non-text
    /// elements, lighter backgrounds get ink; the user can also choose white or black outright.
    public static func lightGlyph(on background: String, glyph: ProfileGlyph = .auto) -> Bool {
        switch glyph {
        case .light: return true
        case .dark: return false
        case .auto: return 1.05 / ((HexColor.luminance(background) ?? 0) + 0.05) >= 3
        }
    }
}
