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
