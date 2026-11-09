import XCTest
@testable import MicaCore

final class DownloadHistoryTests: XCTestCase {
    func testHistorySurvivesReopeningAndAppReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("Profile/downloads.json")
        let record = DownloadRecord(id: UUID(), name: "document.pdf", state: "complete", destination: URL(fileURLWithPath: "/tmp/document.pdf"), bookmark: Data([1, 2, 3]), source: URL(string: "https://example.com/document.pdf"), bytes: 8192, total: 8192, date: Date(timeIntervalSince1970: 1_800_000_000))
        try Persistence.write([record], at: profile)
        let app = root.appendingPathComponent("mica.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: app)
        XCTAssertEqual(try Persistence.read([DownloadRecord].self, at: profile), [record])
        try Persistence.write([record, record], at: profile)
        XCTAssertEqual(try Persistence.read([DownloadRecord].self, at: profile).count, 2)
    }

    func testRecordsWithoutDateStillLoad() throws {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"ki.jpeg","state":"complete","bytes":10,"total":10}]"#
        let records = try JSONDecoder().decode([DownloadRecord].self, from: Data(old.utf8))
        XCTAssertNil(records.first?.date)
        XCTAssertEqual(records.first.map { DownloadKind.of($0.name) }, .image)
    }
}
