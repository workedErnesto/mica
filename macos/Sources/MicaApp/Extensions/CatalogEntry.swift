import AppKit
import WebKit
import CryptoKit
import MicaCore

struct CatalogEntry: Identifiable {
    let id: Int
    let name: String
    let summary: String
    let source: URL
    let version: String
    let permissions: [String]
    /// Signed XPI published by AMO and its SHA-256 from the same HTTPS API response.
    var download: URL?
    var sha256: String?
}
