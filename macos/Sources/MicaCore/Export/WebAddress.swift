import Foundation

/// Reference resolution of RFC 3986 (section 5.2) on plain strings. Foundation and .NET each canonicalise addresses
/// their own way; saving a page needs the same answer on both platforms, so neither is used here.
public enum WebAddress {
    struct Parts { var scheme: String?; var authority: String?; var path: String; var query: String?; var fragment: String? }

    public static func resolve(_ reference: String, against base: String) -> String? {
        let r = parse(SingleFilePage.trim(reference))
        var t = Parts(scheme: nil, authority: nil, path: "", query: nil, fragment: r.fragment)
        if let scheme = r.scheme {
            t.scheme = scheme; t.authority = r.authority; t.path = removeDots(r.path); t.query = r.query
        } else {
            let b = parse(base)
            guard let scheme = b.scheme else { return nil }
            t.scheme = scheme
            if let authority = r.authority {
                t.authority = authority; t.path = removeDots(r.path); t.query = r.query
            } else {
                t.authority = b.authority
                if r.path.isEmpty { t.path = b.path; t.query = r.query ?? b.query }
                else {
                    if r.path.hasPrefix("/") { t.path = removeDots(r.path) }
                    else if b.authority != nil && b.path.isEmpty { t.path = removeDots("/" + r.path) }
                    else { t.path = removeDots((b.path.lastIndex(of: "/").map { String(b.path[...$0]) } ?? "") + r.path) }
                    t.query = r.query
                }
            }
        }
        var result = (t.scheme ?? "") + ":"
        if let authority = t.authority { result += "//" + authority }
        result += t.path
        if let query = t.query { result += "?" + query }
        if let fragment = t.fragment { result += "#" + fragment }
        return result
    }

    static func parse(_ text: String) -> Parts {
        var rest = Substring(text)
        var parts = Parts(scheme: nil, authority: nil, path: "", query: nil, fragment: nil)
        if let hash = rest.firstIndex(of: "#") { parts.fragment = String(rest[rest.index(after: hash)...]); rest = rest[..<hash] }
        if let mark = rest.firstIndex(of: "?") { parts.query = String(rest[rest.index(after: mark)...]); rest = rest[..<mark] }
        if let colon = rest.firstIndex(of: ":"), colon != rest.startIndex, !rest[..<colon].contains("/") {
            let name = rest[..<colon]
            let valid = name.unicodeScalars.enumerated().allSatisfy { index, c in
                (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (index > 0 && ((c >= "0" && c <= "9") || c == "+" || c == "-" || c == "."))
            }
            if valid { parts.scheme = name.lowercased(); rest = rest[rest.index(after: colon)...] }
        }
        if rest.hasPrefix("//") {
            rest = rest.dropFirst(2)
            let end = rest.firstIndex(of: "/") ?? rest.endIndex
            parts.authority = String(rest[..<end]); rest = rest[end...]
        }
        parts.path = String(rest)
        return parts
    }

    static func removeDots(_ path: String) -> String {
        var input = Substring(path)
        var result = ""
        while !input.isEmpty {
            if input.hasPrefix("../") { input = input.dropFirst(3) }
            else if input.hasPrefix("./") { input = input.dropFirst(2) }
            else if input.hasPrefix("/./") { input = input.dropFirst(2) }
            else if input == "/." { input = "/" }
            else if input.hasPrefix("/../") { input = input.dropFirst(3); result = dropLastSegment(result) }
            else if input == "/.." { input = "/"; result = dropLastSegment(result) }
            else if input == "." || input == ".." { input = "" }
            else {
                let start = input.hasPrefix("/") ? input.index(after: input.startIndex) : input.startIndex
                let end = input[start...].firstIndex(of: "/") ?? input.endIndex
                result += input[..<end]; input = input[end...]
            }
        }
        return result
    }

    static func dropLastSegment(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}
