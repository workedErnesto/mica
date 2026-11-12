import Foundation

/// What mica tells its Dock tile plug-in (Sources/MicaDockTile) about the chosen app icon. This file is also compiled
/// into the plug-in by scripts/build.sh, so it uses Foundation only.
///
/// The plug-in cannot read mica's preferences: since macOS 14 the system denies other processes the data container of
/// a sandboxed app, and the Dock's plug-in host got exactly that ("System Policy: com.apple.dock.external.extra
/// deny file-read-data .../Containers/app.mica.browser/.../preferences.json"). A sandboxed app may post a distributed
/// notification only without userInfo, but a string object is delivered, so the choice travels in the object.
public enum DockIcon {
    public static let notification = "app.mica.browser.appIconChanged"
    /// The bundle icon is drawn from this one.
    public static let standard = "base-original"

    public static func valid(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// "<icon>:<app bundle path>". The path keeps a debug build in another folder from changing the installed copy.
    public static func message(icon: String?, bundle: String) -> String {
        let id = icon.flatMap { valid($0) ? $0 : nil } ?? standard
        return id + ":" + normalized(bundle)
    }

    /// The icon in a message meant for the app at `bundle`, nil for a malformed message or another copy of mica.
    public static func icon(in message: String, bundle: String) -> String? {
        guard let colon = message.firstIndex(of: ":") else { return nil }
        let id = String(message[..<colon]), path = String(message[message.index(after: colon)...])
        guard valid(id), !path.isEmpty, normalized(path) == normalized(bundle) else { return nil }
        return id
    }

    static func normalized(_ path: String) -> String {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}
