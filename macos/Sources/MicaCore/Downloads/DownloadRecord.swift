import Foundation

/// Durable metadata. Downloaded files stay at their user-selected destinations.
public struct DownloadRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var state: String
    public var destination: URL?
    public var bookmark: Data?
    public var source: URL?
    public var bytes: Int64
    public var total: Int64
    /// When the download started. Older records have none; the app fills it once from the file on disk.
    public var date: Date?
    public init(id: UUID, name: String, state: String, destination: URL?, bookmark: Data?, source: URL?, bytes: Int64, total: Int64, date: Date? = nil) {
        self.id = id; self.name = name; self.state = state; self.destination = destination
        self.bookmark = bookmark; self.source = source; self.bytes = bytes; self.total = total; self.date = date
    }
}
