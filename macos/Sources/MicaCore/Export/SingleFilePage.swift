import Foundation

/// A file the page loaded: an image, a stylesheet, a font. macOS takes them from WebKit's web archive, Windows from
/// the DevTools resource tree.
public struct PageResource: Sendable {
    public var url: String
    public var mime: String
    public var data: Data
    public init(url: String, mime: String, data: Data) { self.url = url; self.mime = mime; self.data = data }
}

/// Turns a serialised page into one HTML file that opens in any browser without the network: stylesheets become
/// `<style>` blocks, images, fonts and icons become `data:` addresses. Scripts, event handlers, `<base>`, content
/// security policies and preload hints are removed, so the saved copy shows the page as it was and fetches nothing
/// of its own. A file the page never loaded (an image further down that was not requested) keeps its absolute
/// address. The input is a browser serialisation (`outerHTML`), so tags are well formed and attribute values quoted;
/// all work is on ASCII delimiters, which keeps macOS and Windows byte for byte equal (vectors `singleFilePage`).
public enum SingleFilePage {
    /// Larger files (videos, mostly) stay as links: inlined they would make the page too heavy to open.
    public static let maxInlineBytes = 32 * 1024 * 1024

    public static func build(html: String, base: String, resources: [PageResource]) -> String {
        var map: [String: PageResource] = [:]
        for resource in resources where map[key(resource.url)] == nil { map[key(resource.url)] = resource }
        var builder = Builder(map: map, base: base)
        return builder.run(Array(html.utf8))
    }

    static func key(_ url: String) -> String { url.firstIndex(of: "#").map { String(url[..<$0]) } ?? url }

    // MARK: HTML

    struct Attribute {
        var name: String
        var raw: ArraySlice<UInt8>
        var value: ArraySlice<UInt8>?
        var replacement: String??
    }

    struct Tag {
        var name: String
        var rawName: ArraySlice<UInt8>
        var attributes: [Attribute]
        var selfClosing: Bool
        var end: Int
        var changed = false
        func value(_ name: String) -> String? { attributes.first { $0.name == name }.flatMap { $0.value.map(decode) } }
        func has(_ name: String) -> Bool { attributes.contains { $0.name == name } }
        mutating func setIfChanged(_ name: String, _ value: String) {
            guard let index = attributes.firstIndex(where: { $0.name == name }), self.value(name) != value else { return }
            attributes[index].replacement = .some(value); changed = true
        }
    }

    struct Builder {
        let map: [String: PageResource]
        let base: String
        var out: [UInt8] = []
        var charset = false

        init(map: [String: PageResource], base: String) { self.map = map; self.base = base }

        mutating func run(_ b: [UInt8]) -> String {
            let n = b.count
            out.reserveCapacity(n)
            var i = 0
            while i < n {
                if starts(b, i, "<!--") {
                    let end = find(b, "-->", from: i + 4).map { $0 + 3 } ?? n
                    out.append(contentsOf: b[i..<end]); i = end; continue
                }
                if b[i] == 0x3C, i + 1 < n {
                    let next = b[i + 1]
                    if next == 0x21 || next == 0x3F || next == 0x2F {
                        // Doctype, processing instruction or closing tag: copied as they are.
                        let end = (b[i...].firstIndex(of: 0x3E) ?? n - 1) + 1
                        out.append(contentsOf: b[i..<end]); i = end; continue
                    }
                    if isLetter(next), var tag = parseTag(b, i) {
                        i = handle(&tag, b, from: i)
                        continue
                    }
                }
                out.append(b[i]); i += 1
            }
            if !charset {
                let meta = Array("<meta charset=\"utf-8\">".utf8)
                if starts(out, 0, "<!DOCTYPE") || starts(out, 0, "<!doctype"), let close = out.firstIndex(of: 0x3E) { out.insert(contentsOf: meta, at: close + 1) }
                else { out.insert(contentsOf: meta, at: 0) }
            }
            return String(decoding: out, as: UTF8.self)
        }

        /// Writes the tag (and for script and style, their content) and returns where scanning continues.
        mutating func handle(_ tag: inout Tag, _ b: [UInt8], from start: Int) -> Int {
            switch tag.name {
            case "script":
                if tag.selfClosing { return tag.end }
                guard let close = findInsensitive(b, "</script", from: tag.end) else { return b.count }
                return (b[close...].firstIndex(of: 0x3E) ?? b.count - 1) + 1
            case "base":
                return tag.end
            case "meta":
                let equiv = tag.value("http-equiv")?.lowercased()
                if tag.has("charset") || equiv == "content-security-policy" || equiv == "content-type" { return tag.end }
            case "link":
                let rel = Set((tag.value("rel") ?? "").lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init))
                if !rel.isDisjoint(with: ["preload", "prefetch", "modulepreload", "preconnect", "dns-prefetch", "prerender", "manifest"]) { return tag.end }
                if rel.contains("stylesheet"), !rel.contains("alternate"), let href = tag.value("href"),
                   let target = resolve(href), let sheet = map[key(target)] {
                    var css = Array(styleSheet(sheet, depth: 0, seen: [key(target)]).utf8)
                    css = escapeStyleEnd(css)
                    out.append(contentsOf: Array("<style".utf8))
                    if let media = tag.attributes.first(where: { $0.name == "media" }) { out.append(0x20); out.append(contentsOf: media.raw) }
                    out.append(0x3E); out.append(contentsOf: css); out.append(contentsOf: Array("</style>".utf8))
                    return tag.end
                }
                if let href = tag.value("href") {
                    let icon = rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("mask-icon")
                    tag.setIfChanged("href", icon ? media(href) : link(href))
                }
            default: break
            }
            rewriteAttributes(&tag)
            write(tag, b, from: start)
            if tag.name == "head" && !charset { out.append(contentsOf: Array("<meta charset=\"utf-8\">".utf8)); charset = true }
            if tag.name == "style", !tag.selfClosing {
                let close = findInsensitive(b, "</style", from: tag.end) ?? b.count
                let css = String(decoding: b[tag.end..<close], as: UTF8.self)
                out.append(contentsOf: escapeStyleEnd(Array(rewriteCSS(css, base: base, depth: 0, seen: []).utf8)))
                return close
            }
            return tag.end
        }

        mutating func rewriteAttributes(_ tag: inout Tag) {
            let name = tag.name
            let hasSource = tag.has("src")
            for index in tag.attributes.indices {
                let attribute = tag.attributes[index]
                guard attribute.replacement == nil else { continue }
                let key = attribute.name
                if key.count > 2, key.hasPrefix("on") { tag.attributes[index].replacement = .some(nil); tag.changed = true; continue }
                guard let raw = attribute.value else { continue }
                let value = decode(raw)
                var next: String?
                switch key {
                case "style": next = rewriteCSS(value, base: base, depth: 0, seen: [])
                case "src":
                    next = ["iframe", "frame"].contains(name) ? link(value) : media(value)
                case "poster", "data", "background", "xlink:href": next = media(value)
                case "href": next = ["image", "use", "feimage"].contains(name) ? media(value) : link(value)
                case "action", "cite", "formaction": next = link(value)
                case "srcset", "sizes":
                    if hasSource { tag.attributes[index].replacement = .some(nil); tag.changed = true; continue }
                    if key == "srcset" { next = srcset(value) }
                default: break
                }
                if let next, next != value { tag.attributes[index].replacement = .some(next); tag.changed = true }
            }
        }

        mutating func write(_ tag: Tag, _ b: [UInt8], from start: Int) {
            guard tag.changed else { out.append(contentsOf: b[start..<tag.end]); return }
            out.append(0x3C); out.append(contentsOf: tag.rawName)
            for attribute in tag.attributes {
                switch attribute.replacement {
                case .none: out.append(0x20); out.append(contentsOf: attribute.raw)
                case .some(.none): continue
                case .some(.some(let value)):
                    out.append(0x20); out.append(contentsOf: Array(attribute.name.utf8))
                    out.append(contentsOf: Array("=\"".utf8)); out.append(contentsOf: Array(encode(value).utf8)); out.append(0x22)
                }
            }
            out.append(contentsOf: tag.selfClosing ? Array("/>".utf8) : [0x3E])
        }

        // MARK: Addresses

        func resolve(_ value: String) -> String? { WebAddress.resolve(value, against: base) }

        /// A link keeps working after saving: absolute, except an anchor inside the page.
        func link(_ value: String) -> String {
            let trimmed = trim(value)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return value }
            return resolve(trimmed) ?? value
        }

        /// A file the page shows: inside the file when the page loaded it, otherwise its absolute address.
        func media(_ value: String, base other: String? = nil) -> String {
            let trimmed = trim(value)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty || trimmed.hasPrefix("#") || lower.hasPrefix("data:") || lower.hasPrefix("blob:") || lower.hasPrefix("javascript:") || lower.hasPrefix("about:") { return value }
            guard let target = WebAddress.resolve(trimmed, against: other ?? base) else { return value }
            if let resource = map[key(target)], resource.data.count <= SingleFilePage.maxInlineBytes { return dataAddress(resource) }
            return target
        }

        func srcset(_ value: String) -> String {
            if value.lowercased().contains("data:") { return value }
            return value.split(separator: ",").map { candidate -> String in
                let parts = trim(String(candidate)).split(separator: " ", maxSplits: 1).map(String.init)
                guard let first = parts.first else { return String(candidate) }
                return ([media(first)] + parts.dropFirst()).joined(separator: " ")
            }.joined(separator: ", ")
        }

        // MARK: CSS

        func styleSheet(_ sheet: PageResource, depth: Int, seen: Set<String>) -> String {
            var text = String(decoding: sheet.data, as: UTF8.self)
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return rewriteCSS(text, base: sheet.url, depth: depth, seen: seen)
        }

        /// Rewrites `url()` and `@import` of a stylesheet whose relative addresses count from `base`.
        func rewriteCSS(_ css: String, base: String, depth: Int, seen: Set<String>) -> String {
            let b = Array(css.utf8), n = b.count
            var out: [UInt8] = []; out.reserveCapacity(n)
            var i = 0
            while i < n {
                let c = b[i]
                if c == 0x2F, i + 1 < n, b[i + 1] == 0x2A {
                    let end = find(b, "*/", from: i + 2).map { $0 + 2 } ?? n
                    out.append(contentsOf: b[i..<end]); i = end; continue
                }
                if c == 0x40, startsInsensitive(b, i, "@import"), let (reference, media, end) = parseImport(b, i + 7) {
                    out.append(contentsOf: Array(importRule(reference, media: media, base: base, depth: depth, seen: seen).utf8))
                    i = end; continue
                }
                if (c == 0x75 || c == 0x55), startsInsensitive(b, i, "url("), i == 0 || !isIdent(b[i - 1]), let (value, end) = parseURL(b, i + 4) {
                    let trimmed = trim(value)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.lowercased().hasPrefix("data:") { out.append(contentsOf: b[i..<end]) }
                    else { out.append(contentsOf: Array(("url(\"" + cssQuote(media(trimmed, base: base)) + "\")").utf8)) }
                    i = end; continue
                }
                if c == 0x22 || c == 0x27 {
                    let end = stringEnd(b, i)
                    out.append(contentsOf: b[i..<end]); i = end; continue
                }
                out.append(c); i += 1
            }
            return String(decoding: out, as: UTF8.self)
        }

        func importRule(_ reference: String, media: String, base: String, depth: Int, seen: Set<String>) -> String {
            let target = WebAddress.resolve(trim(reference), against: base)
            let lower = media.lowercased()
            let conditional = lower.hasPrefix("layer") || lower.hasPrefix("supports")
            if let target, depth < 4, !conditional, !seen.contains(key(target)), let sheet = map[key(target)] {
                let inner = styleSheet(sheet, depth: depth + 1, seen: seen.union([key(target)]))
                return media.isEmpty ? inner : "@media " + media + " {\n" + inner + "\n}"
            }
            return "@import url(\"" + cssQuote(target ?? reference) + "\")" + (media.isEmpty ? "" : " " + media) + ";"
        }

        /// After `url(`: the address and the index after `)`.
        func parseURL(_ b: [UInt8], _ from: Int) -> (String, Int)? {
            var j = from
            while j < b.count, isSpace(b[j]) { j += 1 }
            guard j < b.count else { return nil }
            if b[j] == 0x22 || b[j] == 0x27 {
                let end = stringEnd(b, j)
                let value = String(decoding: b[(j + 1)..<max(j + 1, end - 1)], as: UTF8.self)
                var k = end
                while k < b.count, isSpace(b[k]) { k += 1 }
                guard k < b.count, b[k] == 0x29 else { return nil }
                return (value, k + 1)
            }
            guard let close = b[j...].firstIndex(of: 0x29) else { return nil }
            return (String(decoding: b[j..<close], as: UTF8.self), close + 1)
        }

        /// After `@import`: the address, the media list and the index after `;`.
        func parseImport(_ b: [UInt8], _ from: Int) -> (String, String, Int)? {
            var j = from
            while j < b.count, isSpace(b[j]) { j += 1 }
            guard j < b.count else { return nil }
            var reference: String
            if startsInsensitive(b, j, "url("), let (value, end) = parseURL(b, j + 4) { reference = value; j = end }
            else if b[j] == 0x22 || b[j] == 0x27 { let end = stringEnd(b, j); reference = String(decoding: b[(j + 1)..<max(j + 1, end - 1)], as: UTF8.self); j = end }
            else { return nil }
            let semicolon = b[j...].firstIndex(of: 0x3B) ?? b.count
            let media = trim(String(decoding: b[j..<semicolon], as: UTF8.self))
            reference = trim(reference)
            return (reference, media, min(b.count, semicolon + 1))
        }

        func dataAddress(_ resource: PageResource) -> String {
            var mime = trim(String(resource.mime.split(separator: ";", omittingEmptySubsequences: false).first ?? "")).lowercased()
            if mime.isEmpty { mime = "application/octet-stream" }
            return "data:" + mime + ";base64," + resource.data.base64EncodedString()
        }
    }

    // MARK: Scanning

    static func parseTag(_ b: [UInt8], _ start: Int) -> Tag? {
        let n = b.count
        var j = start + 1
        while j < n, isLetter(b[j]) || isDigit(b[j]) || b[j] == 0x2D || b[j] == 0x3A || b[j] == 0x5F { j += 1 }
        let rawName = b[(start + 1)..<j]
        var tag = Tag(name: String(decoding: rawName, as: UTF8.self).lowercased(), rawName: rawName, attributes: [], selfClosing: false, end: n)
        while true {
            while j < n, isSpace(b[j]) { j += 1 }
            guard j < n else { return nil }
            if b[j] == 0x3E { tag.end = j + 1; return tag }
            if b[j] == 0x2F {
                if j + 1 < n, b[j + 1] == 0x3E { tag.selfClosing = true; tag.end = j + 2; return tag }
                j += 1; continue
            }
            let begin = j
            j += 1
            while j < n, !isSpace(b[j]), b[j] != 0x3D, b[j] != 0x3E, !(b[j] == 0x2F && j + 1 < n && b[j + 1] == 0x3E) { j += 1 }
            let name = String(decoding: b[begin..<j], as: UTF8.self).lowercased()
            var k = j
            while k < n, isSpace(b[k]) { k += 1 }
            var value: ArraySlice<UInt8>?
            if k < n, b[k] == 0x3D {
                k += 1
                while k < n, isSpace(b[k]) { k += 1 }
                guard k < n else { return nil }
                if b[k] == 0x22 || b[k] == 0x27 {
                    let quote = b[k]
                    guard let close = b[(k + 1)...].firstIndex(of: quote) else { return nil }
                    value = b[(k + 1)..<close]; j = close + 1
                } else {
                    var e = k
                    while e < n, !isSpace(b[e]), b[e] != 0x3E { e += 1 }
                    value = b[k..<e]; j = e
                }
            }
            tag.attributes.append(Attribute(name: name, raw: b[begin..<j], value: value, replacement: nil))
        }
    }

    static func decode(_ raw: ArraySlice<UInt8>) -> String {
        let text = String(decoding: raw, as: UTF8.self)
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[amp...]
            guard let semi = tail.prefix(12).firstIndex(of: ";") else { result += "&"; rest = rest[rest.index(after: amp)...]; continue }
            let entity = String(tail[tail.index(after: amp)..<semi])
            var scalar: Unicode.Scalar?
            switch entity {
            case "amp": scalar = "&"
            case "quot": scalar = "\""
            case "apos": scalar = "'"
            case "lt": scalar = "<"
            case "gt": scalar = ">"
            case "nbsp": scalar = "\u{00A0}"
            default:
                // Digits only: Swift's integer parsing would also take a sign, .NET's (and the HTML spec) do not.
                let hex = entity.hasPrefix("#x") || entity.hasPrefix("#X")
                let digits = entity.hasPrefix("#") ? entity.dropFirst(hex ? 2 : 1) : ""
                if !digits.isEmpty, digits.allSatisfy({ hex ? $0.isHexDigit && $0.isASCII : ("0"..."9").contains($0) }) {
                    scalar = UInt32(digits, radix: hex ? 16 : 10).flatMap(Unicode.Scalar.init)
                }
            }
            if let scalar { result.unicodeScalars.append(scalar); rest = rest[rest.index(after: semi)...] }
            else { result += "&"; rest = rest[rest.index(after: amp)...] }
        }
        return result + rest
    }

    static func encode(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "\u{00A0}": result += "&nbsp;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func cssQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "%5C").replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
    }

    static func escapeStyleEnd(_ css: [UInt8]) -> [UInt8] {
        guard findInsensitive(css, "</style", from: 0) != nil else { return css }
        var out: [UInt8] = []; var i = 0
        while i < css.count {
            if startsInsensitive(css, i, "</style") { out.append(contentsOf: Array("<\\/style".utf8)); i += 7; continue }
            out.append(css[i]); i += 1
        }
        return out
    }

    /// Index after a CSS string starting at `start` (its quote), honouring backslash escapes; a newline ends it.
    static func stringEnd(_ b: [UInt8], _ start: Int) -> Int {
        let quote = b[start]
        var j = start + 1
        while j < b.count {
            if b[j] == 0x5C { j += 2; continue }
            if b[j] == quote { return j + 1 }
            if b[j] == 0x0A { return j }
            j += 1
        }
        return b.count
    }

    static func trim(_ s: String) -> String {
        var scalars = Substring(s).unicodeScalars[...]
        while let f = scalars.first, f == " " || f == "\t" || f == "\n" || f == "\r" || f == "\u{0C}" { scalars = scalars.dropFirst() }
        while let l = scalars.last, l == " " || l == "\t" || l == "\n" || l == "\r" || l == "\u{0C}" { scalars = scalars.dropLast() }
        var out = ""; out.unicodeScalars.append(contentsOf: scalars); return out
    }

    static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C }
    static func isLetter(_ c: UInt8) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isIdent(_ c: UInt8) -> Bool { isLetter(c) || isDigit(c) || c == 0x2D || c == 0x5F || c >= 0x80 }

    static func starts(_ b: [UInt8], _ i: Int, _ text: String) -> Bool {
        let t = Array(text.utf8)
        guard i + t.count <= b.count else { return false }
        for k in 0..<t.count where b[i + k] != t[k] { return false }
        return true
    }

    static func startsInsensitive(_ b: [UInt8], _ i: Int, _ text: String) -> Bool {
        let t = Array(text.lowercased().utf8)
        guard i + t.count <= b.count else { return false }
        for k in 0..<t.count {
            var c = b[i + k]
            if c >= 0x41 && c <= 0x5A { c += 32 }
            if c != t[k] { return false }
        }
        return true
    }

    static func find(_ b: [UInt8], _ text: String, from: Int) -> Int? {
        var i = from
        while i < b.count { if starts(b, i, text) { return i }; i += 1 }
        return nil
    }

    static func findInsensitive(_ b: [UInt8], _ text: String, from: Int) -> Int? {
        var i = from
        while i < b.count { if startsInsensitive(b, i, text) { return i }; i += 1 }
        return nil
    }
}
