import Foundation

/// Start page greeting. The name is user data and keeps its spelling; only the authored words follow the case style.
public enum Greeting {
    /// Phrases for the moment of day; `{name}` marks the name.
    public static func phrases(hour: Int, language: Language) -> [(low: String, regular: String)] {
        switch language {
        case .ru:
            let time: (String, String) = (5..<12).contains(hour) ? ("доброе утро, {name}", "Доброе утро, {name}") : (12..<18).contains(hour) ? ("добрый день, {name}", "Добрый день, {name}") : (18..<24).contains(hour) ? ("добрый вечер, {name}", "Добрый вечер, {name}") : ("не спится, {name}?", "Не спится, {name}?")
            return [time, ("привет, {name}", "Привет, {name}"), ("{name}, чем займёмся?", "{name}, чем займёмся?"), ("с возвращением, {name}", "С возвращением, {name}"), ("что ищем, {name}?", "Что ищем, {name}?"), ("куда сегодня, {name}?", "Куда сегодня, {name}?"), ("{name}, что откроем?", "{name}, что откроем?")]
        case .en:
            let time: (String, String) = (5..<12).contains(hour) ? ("good morning, {name}", "Good morning, {name}") : (12..<18).contains(hour) ? ("good afternoon, {name}", "Good afternoon, {name}") : (18..<24).contains(hour) ? ("good evening, {name}", "Good evening, {name}") : ("up late, {name}?", "Up late, {name}?")
            return [time, ("hi, {name}", "Hi, {name}"), ("{name}, what's next?", "{name}, what's next?"), ("welcome back, {name}", "Welcome back, {name}"), ("where to, {name}?", "Where to, {name}?"), ("what are we looking for, {name}?", "What are we looking for, {name}?"), ("{name}, what shall we open?", "{name}, what shall we open?")]
        }
    }
    /// nil when there is no name or the user asked not to be addressed by it. `seed` picks the phrase.
    public static func text(_ preferences: Preferences, hour: Int, seed: Int) -> String? {
        let name = preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.greetByName, !name.isEmpty else { return nil }
        let list = phrases(hour: hour, language: preferences.language)
        let phrase = list[((seed % list.count) + list.count) % list.count]
        return (preferences.lowercase ? phrase.low : phrase.regular).replacingOccurrences(of: "{name}", with: name)
    }
}
