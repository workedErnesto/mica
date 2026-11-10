import Foundation

public struct Visit: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var url: URL
    public var title: String
    public var date = Date()
    /// Profile of the window the page was opened in. nil for visits recorded before profiles, which belong to the standard one.
    public var profile: UUID?
    public init(url: URL, title: String, profile: UUID? = nil) { self.url = url; self.title = title; self.profile = profile }
}
