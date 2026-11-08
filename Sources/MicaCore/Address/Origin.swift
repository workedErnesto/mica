import Foundation

public enum Origin {
    public static func string(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        let port = url.port
        return "\(scheme)://\(host)" + ((port == nil || port == (scheme == "https" ? 443 : 80)) ? "" : ":\(port!)")
    }
    public static func secure(_ origin: String) -> Bool { origin.hasPrefix("https://") }
}
