import Foundation

public struct Visit: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var url: URL
    public var title: String
    public var date = Date()
    public init(url: URL, title: String) { self.url = url; self.title = title }
}
