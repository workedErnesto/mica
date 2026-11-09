import Foundation

public enum DownloadState: String, Sendable { case choosing, running, complete, failed, cancelled }

public enum DownloadSafety {
    public static func filename(_ proposed: String) -> String {
        let last = (proposed as NSString).lastPathComponent
        let clean = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" && $0 != "/" }
        let name = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." ? "download" : String(name.prefix(200))
    }
}

/// What a downloaded file is, by its extension: picks the icon of a finished download. Lists match Windows exactly
/// (shared vectors), so the same file shows the same kind on both platforms.
public enum DownloadKind: String, Sendable, CaseIterable {
    case image, video, archive, document, other

    static let extensions: [DownloadKind: Set<String>] = [
        .image: ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff", "svg", "ico", "raw", "dng", "cr2", "nef", "arw"],
        .video: ["mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "m2ts"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "lz", "lzma", "cab", "dmg", "iso", "pkg"],
        .document: ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "pages", "xls", "xlsx", "ods", "csv", "numbers", "ppt", "pptx", "odp", "key", "epub", "djvu", "fb2"],
    ]

    public static func of(_ name: String) -> DownloadKind {
        let dot = name.lastIndex(of: ".")
        guard let dot, dot != name.startIndex else { return .other }
        let ext = name[name.index(after: dot)...].lowercased()
        return [.image, .video, .archive, .document].first { extensions[$0]!.contains(ext) } ?? .other
    }
}
