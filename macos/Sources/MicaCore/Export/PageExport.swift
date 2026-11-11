import Foundation

/// Formats a page can be saved in. PDF is paginated by the print system with the page's print styles; PNG and JPEG
/// picture the whole page as on screen; HTML is one file with the page's images, styles and fonts inside it.
public enum PageFormat: String, CaseIterable, Codable, Sendable {
    case pdf, png, jpeg, html
    public var fileExtension: String {
        switch self { case .pdf: return "pdf"; case .png: return "png"; case .jpeg: return "jpg"; case .html: return "html" }
    }
}

/// Rules for saving a page shared with Windows (vectors `pageFileName`, `pageImage`).
public enum PageExport {
    /// The longest side of a saved picture. Chromium cannot capture past 16384 px and a bitmap of that height already
    /// takes hundreds of megabytes, so both platforms stop there and scale a longer page down.
    public static let maxImageSide = 16384.0
    public static let maxImagePixels = 64_000_000.0

    /// Pixel size of a picture of a page `width` by `height` points at the screen's `scale`, reduced to fit the limits,
    /// or nil for an empty page.
    public static func imagePixels(width: Double, height: Double, scale: Double) -> (width: Int, height: Int)? {
        guard width >= 1, height >= 1, scale > 0 else { return nil }
        var s = scale
        s = min(s, maxImageSide / width, maxImageSide / height)
        if width * height * s * s > maxImagePixels { s = (maxImagePixels / (width * height)).squareRoot() }
        return (max(1, Int((width * s).rounded(.down))), max(1, Int((height * s).rounded(.down))))
    }

    static let reserved: Set<String> = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

    /// Proposed file name: the page title, else its host without `www.`, else "page". Slashes and bars become a dash,
    /// other characters macOS or Windows refuse in a name are dropped, runs of spaces become one space; the name is
    /// cut to 120 characters.
    public static func fileName(title: String, url: String?, format: PageFormat) -> String {
        var base = clean(title)
        if base.isEmpty, let url { base = clean(host(url)) }
        if base.isEmpty { base = "page" }
        if reserved.contains(base.split(separator: ".", omittingEmptySubsequences: false).first.map { String($0).uppercased() } ?? "") { base = "_" + base }
        return base + "." + format.fileExtension
    }

    /// The name itself when the folder has no such file, otherwise "name (2).ext", "name (3).ext" and so on.
    public static func availableName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let dot = name.lastIndex(of: ".").flatMap { $0 == name.startIndex ? nil : $0 }
        let base = dot.map { String(name[..<$0]) } ?? name
        let ext = dot.map { String(name[$0...]) } ?? ""
        for number in 2...9999 {
            let candidate = base + " (" + String(number) + ")" + ext
            if !taken(candidate) { return candidate }
        }
        return base + " (" + UUID().uuidString.prefix(8).lowercased() + ")" + ext
    }

    static func clean(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        var space = false
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format && scalar.value != 0x200D || scalar.properties.isWhitespace {
                space = !scalars.isEmpty
                continue
            }
            if ":*?\"<>".unicodeScalars.contains(scalar) { continue }
            if space { scalars.append(" "); space = false }
            scalars.append("/\\|".unicodeScalars.contains(scalar) ? "-" : scalar)
        }
        var result = Array(scalars.prefix(120))
        while let last = result.last, last == " " || last == "." { result.removeLast() }
        while let first = result.first, first == " " || first == "." { result.removeFirst() }
        var string = ""; string.unicodeScalars.append(contentsOf: result)
        return string
    }

    /// Host of an absolute address without user, port and `www.`; plain string work so both platforms agree.
    static func host(_ url: String) -> String {
        guard let range = url.range(of: "://") else { return "" }
        var rest = url[range.upperBound...]
        if let end = rest.firstIndex(where: { "/?#".contains($0) }) { rest = rest[..<end] }
        if let at = rest.lastIndex(of: "@") { rest = rest[rest.index(after: at)...] }
        if rest.hasPrefix("[") { if let close = rest.firstIndex(of: "]") { rest = rest[...close] } }
        else if let colon = rest.lastIndex(of: ":") { rest = rest[..<colon] }
        var host = String(rest).lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Runs in the page before any capture: images marked lazy below the visible part are asked to load now, with a
    /// three-second limit. Returns how many images it waited for.
    public static let prepareScript = """
    const lazy = Array.from(document.images).filter(i => i.loading === 'lazy' || !i.complete);
    for (const image of lazy) image.loading = 'eager';
    await Promise.race([Promise.allSettled(lazy.map(i => i.decode())), new Promise(r => setTimeout(r, 3000))]);
    return lazy.length;
    """

    /// Serialises the page for the HTML file: a copy of the current document (what the page shows now, not the
    /// source it was loaded from) with absolute addresses, the image each `img` actually shows, form values and
    /// canvas pictures. Returns `{html, base, title}`. The live page is not changed.
    public static let serializeScript = """
    const root = document.documentElement, copy = root.cloneNode(true);
    const live = root.querySelectorAll('*'), cloned = copy.querySelectorAll('*');
    const count = Math.min(live.length, cloned.length);
    for (let k = 0; k < count; k++) {
      const a = live[k], b = cloned[k];
      if (a instanceof HTMLImageElement) {
        const src = a.currentSrc || a.src;
        if (src) b.setAttribute('src', src);
        b.removeAttribute('srcset'); b.removeAttribute('sizes'); b.removeAttribute('loading');
      } else if (a instanceof HTMLSourceElement && a.parentElement instanceof HTMLPictureElement) {
        b.remove(); continue;
      } else if (a instanceof HTMLCanvasElement) {
        try {
          const image = document.createElement('img');
          image.src = a.toDataURL();
          for (const name of ['class', 'style', 'width', 'height', 'id']) if (a.hasAttribute(name)) image.setAttribute(name, a.getAttribute(name));
          b.replaceWith(image); continue;
        } catch (e) {}
      } else if (a instanceof HTMLInputElement) {
        if (a.type === 'checkbox' || a.type === 'radio') { if (a.checked) b.setAttribute('checked', ''); else b.removeAttribute('checked'); }
        else if (a.type !== 'password' && a.type !== 'file') b.setAttribute('value', a.value);
      } else if (a instanceof HTMLTextAreaElement) {
        b.textContent = a.value;
      } else if (a instanceof HTMLSelectElement) {
        const options = b.querySelectorAll('option');
        Array.from(a.options).forEach((o, i) => { if (options[i]) { if (o.selected) options[i].setAttribute('selected', ''); else options[i].removeAttribute('selected'); } });
      }
      for (const name of ['src', 'href', 'poster', 'action']) {
        // An image already carries the source it shows (currentSrc), which its src property would undo.
        if (name === 'src' && a instanceof HTMLImageElement) continue;
        const value = b.getAttribute(name);
        if (value === null || value.startsWith('#') || typeof a[name] !== 'string' || !a[name]) continue;
        b.setAttribute(name, a[name]);
      }
    }
    const type = document.doctype;
    return { html: (type ? '<!DOCTYPE ' + type.name + '>' : '') + copy.outerHTML, base: document.baseURI, title: document.title };
    """
}
