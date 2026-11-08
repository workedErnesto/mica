import Foundation

/// Time range for clearing browsing data, counted back from the moment of clearing.
public enum ClearPeriod: String, Codable, CaseIterable, Sendable {
    case hour, day, week, month, all

    /// Oldest moment that is still cleared. `month` is four weeks, as a calendar month has no fixed length.
    public func start(before now: Date) -> Date {
        switch self {
        case .hour: return now.addingTimeInterval(-3600)
        case .day: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return now.addingTimeInterval(-28 * 86_400)
        case .all: return .distantPast
        }
    }
}

/// What the clear-data panel removes. The last choice is remembered in preferences.
public struct ClearChoice: Codable, Equatable, Sendable {
    public var period: ClearPeriod = .hour
    public var history = true
    /// Cookies, local storage, IndexedDB and service workers: sites sign out.
    public var siteData = false
    public var cache = true
    /// Saved site decisions (camera, microphone, notifications) carry no date, so they are cleared for all time.
    public var permissions = false
    public init() {}
    public var isEmpty: Bool { !history && !siteData && !cache && !permissions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClearChoice()
        period = (try? c.decodeIfPresent(ClearPeriod.self, forKey: .period)) ?? d.period
        history = (try? c.decodeIfPresent(Bool.self, forKey: .history)) ?? d.history
        siteData = (try? c.decodeIfPresent(Bool.self, forKey: .siteData)) ?? d.siteData
        cache = (try? c.decodeIfPresent(Bool.self, forKey: .cache)) ?? d.cache
        permissions = (try? c.decodeIfPresent(Bool.self, forKey: .permissions)) ?? d.permissions
    }
}

public enum History {
    /// Visits that remain after clearing everything from `start` on.
    public static func removing(_ visits: [Visit], since start: Date) -> [Visit] { visits.filter { $0.date < start } }

    public static func count(_ visits: [Visit], since start: Date) -> Int { visits.reduce(0) { $1.date >= start ? $0 + 1 : $0 } }

    /// Visits grouped by calendar day, newest day first, keeping the order inside each day.
    public static func days(_ visits: [Visit], calendar: Calendar = .current) -> [(day: Date, visits: [Visit])] {
        var result: [(day: Date, visits: [Visit])] = []
        for visit in visits.sorted(by: { $0.date > $1.date }) {
            let day = calendar.startOfDay(for: visit.date)
            if result.last?.day == day { result[result.count - 1].visits.append(visit) }
            else { result.append((day, [visit])) }
        }
        return result
    }

    /// Every visit to a host, `www.` included, so "delete all from this site" catches both spellings.
    public static func removing(_ visits: [Visit], host: String) -> [Visit] {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return visits.filter { visit in
            guard let h = visit.url.host else { return true }
            return (h.hasPrefix("www.") ? String(h.dropFirst(4)) : h) != bare
        }
    }
}
