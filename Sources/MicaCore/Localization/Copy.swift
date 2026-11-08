import Foundation

/// Interface language. Page content, URLs and user data are never translated.
public enum Language: String, Codable, CaseIterable, Sendable {
    case ru, en
    /// Russian when the system prefers it, English otherwise.
    public static func preferred(_ languages: [String] = Locale.preferredLanguages) -> Language {
        for code in languages {
            if code.hasPrefix("ru") { return .ru }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

public enum Copy {
    // Explicit variants affect only authored UI, never dynamic content or whole strings.
    public static func text(_ low: String, _ regular: String, lowercase: Bool) -> String { lowercase ? low : regular }
    /// Russian variants are written in the source; English ones come from a table keyed by the regular Russian text.
    public static func text(_ low: String, _ regular: String, lowercase: Bool, language: Language) -> String {
        guard language == .en, let english = English.table[regular] else { return lowercase ? low : regular }
        return lowercase ? english.low : english.regular
    }
}
