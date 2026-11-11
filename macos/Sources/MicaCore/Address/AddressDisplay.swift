import Foundation

/// How the address field shows the page address. The default keeps the site name only, every part in the same colour.
public struct AddressStyle: Codable, Equatable, Sendable {
    /// The whole address instead of the site name.
    public var full = false
    /// Subdomains, `www.` among them, in the quieter colour.
    public var dimSubdomain = false
    /// Path, query and fragment in the quieter colour. Only the full address shows them.
    public var dimPath = false
    public init(full: Bool = false, dimSubdomain: Bool = false, dimPath: Bool = false) {
        self.full = full; self.dimSubdomain = dimSubdomain; self.dimPath = dimPath
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        full = (try? c.decodeIfPresent(Bool.self, forKey: .full)) ?? false
        dimSubdomain = (try? c.decodeIfPresent(Bool.self, forKey: .dimSubdomain)) ?? false
        dimPath = (try? c.decodeIfPresent(Bool.self, forKey: .dimPath)) ?? false
    }
}

/// Splits an address into the pieces the address field draws. The registrable domain (site.com in sub.site.com)
/// and the port always keep the main colour, so the site the page belongs to stays readable.
/// The split is textual and identical on Windows (shared vectors `addressDisplay`).
public enum AddressDisplay {
    public struct Part: Equatable, Sendable {
        public var text: String
        public var dim: Bool
        public init(_ text: String, dim: Bool) { self.text = text; self.dim = dim }
    }

    public static func parts(_ address: String, style: AddressStyle) -> [Part] {
        var result: [Part] = []
        func add(_ text: String, _ dim: Bool) {
            guard !text.isEmpty else { return }
            if let last = result.last, last.dim == dim { result[result.count - 1].text += text } else { result.append(Part(text, dim: dim)) }
        }
        guard let mark = address.range(of: "://"), address[..<mark.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }), !address[..<mark.lowerBound].isEmpty else {
            add(address, false)
            return result
        }
        let scheme = address[..<mark.lowerBound].lowercased()
        let afterScheme = address[mark.upperBound...]
        let authorityEnd = afterScheme.firstIndex { "/?#".contains($0) } ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        var rest = String(afterScheme[authorityEnd...])
        if scheme == "file" {
            let path = decodedFully(rest.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rest)
            if style.full { add(path.isEmpty ? "/" : path, false) } else {
                let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
                add(trimmed.split(separator: "/").last.map(String.init) ?? "/", false)
            }
            return result
        }
        let userEnd = authority.lastIndex(of: "@").map { authority.index(after: $0) } ?? authority.startIndex
        let user = String(authority[..<userEnd])
        let hostPort = authority[userEnd...]
        var host: String, port: String
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            host = String(hostPort[...close]); port = String(hostPort[hostPort.index(after: close)...])
        } else if let colon = hostPort.firstIndex(of: ":") {
            host = String(hostPort[..<colon]); port = String(hostPort[colon...])
        } else { host = String(hostPort); port = "" }
        if host.isEmpty { add(address, false); return result }
        let split = registrableStart(host)
        var sub = String(host[..<split]), domain = String(host[split...])
        if !style.full {
            if sub.hasPrefix("www.") { sub.removeFirst(4) }
            if domain.hasPrefix("[") && domain.hasSuffix("]") { domain = String(domain.dropFirst().dropLast()) }
            add(sub, style.dimSubdomain)
            add(domain, false)
            return result
        }
        if rest == "/" { rest = "" }
        // Web addresses start at the host: the lock in the field already tells https from http, and sign-in names
        // before @ are not shown. Other schemes keep their prefix so they are not mistaken for a web page.
        if !["http", "https"].contains(scheme) { add(scheme + "://" + user, style.dimPath) }
        add(sub, style.dimSubdomain)
        add(domain + port, false)
        add(decodedText(rest), style.dimPath)
        return result
    }

    /// Second-level labels under a country code that are sold as one public suffix (example.co.uk, site.com.au, site.msk.ru).
    static let countrySecondLevel: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "gob", "mil", "ltd", "plc", "sch", "nhs", "msk", "spb"]

    /// Where the registrable domain begins: the last two labels, or three under a two-letter country code with a known
    /// second level. IP addresses and single-label hosts are kept whole.
    static func registrableStart(_ host: String) -> String.Index {
        if host.hasPrefix("[") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host.startIndex }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 2 else { return host.startIndex }
        let tld = labels[labels.count - 1], second = labels[labels.count - 2]
        let keep = tld.count == 2 && countrySecondLevel.contains(second.lowercased()) ? 3 : 2
        guard labels.count > keep else { return host.startIndex }
        let dropped = labels.dropLast(keep).reduce(0) { $0 + $1.count + 1 }
        return host.index(host.startIndex, offsetBy: dropped)
    }

    /// Percent escapes of non-ASCII text become readable letters (/wiki/Москва), ASCII escapes such as %20 and %2F stay
    /// as written. A run that is not valid UTF-8, or that decodes to control, format or separator characters (which could
    /// hide or reorder the address), stays encoded.
    static func decodedText(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var output = ""
        var index = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
        func escaped(at i: Int) -> UInt8? {
            guard i + 2 < bytes.count, bytes[i] == 37, let high = hex(bytes[i + 1]), let low = hex(bytes[i + 2]) else { return nil }
            return high << 4 | low
        }
        var plainStart = 0
        while index < bytes.count {
            guard let first = escaped(at: index), first >= 0x80 else { index += 1; continue }
            var run: [UInt8] = []
            var end = index
            while let value = escaped(at: end), value >= 0x80 { run.append(value); end += 3 }
            output += String(decoding: bytes[plainStart..<index], as: UTF8.self)
            if let decoded = String(bytes: run, encoding: .utf8), decoded.unicodeScalars.allSatisfy(readable) {
                output += decoded
            } else {
                output += String(decoding: bytes[index..<end], as: UTF8.self)
            }
            index = end; plainStart = end
        }
        output += String(decoding: bytes[plainStart...], as: UTF8.self)
        return output
    }

    static func readable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: return false
        default: return true
        }
    }

    static func decodedFully(_ text: String) -> String { text.removingPercentEncoding ?? text }
}
