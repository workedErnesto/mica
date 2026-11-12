import AppKit
import WebKit
import CryptoKit
import MicaCore

struct CatalogEntry: Identifiable {
    let id: Int
    /// Add-on ID from the manifest, as AMO lists it.
    let guid: String
    let name: String
    let summary: String
    let source: URL
    let version: String
    let permissions: [String]
    /// Signed XPI published by AMO and its SHA-256 from the same HTTPS API response.
    var download: URL?
    var sha256: String?
    /// Icon on AMO's own host.
    var icon: URL?
    var isUBlock: Bool { guid == UBlockEngine.geckoID }
}
