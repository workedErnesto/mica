import AppKit
import SwiftUI
import ImageIO
import MicaCore

/// Dock icons converted from the Orbit pack (scripts/app-icons.swift). While mica runs they change its icon in the Dock
/// and the app switcher; the Dock tile plug-in keeps the choice on a quit mica's tile and on the bundle for Finder and
/// Launchpad. Nothing inside the window uses them except the picker.
@MainActor
enum AppIcons {
    struct Icon: Identifiable { let id: String; let low: String; let regular: String }
    /// Set names follow the interface case style on the owner's request, the universes included.
    struct IconSet: Identifiable { let id: String; let low: String; let regular: String; let icons: [Icon] }
    /// The bundle icon is drawn from this one, so "no custom icon" and this choice are the same.
    static let standard = "base-original"
    static let sets: [IconSet] = [
        IconSet(id: "base", low: "стандартные", regular: "Стандартные", icons: [
            Icon(id: "base-original", low: "исходная", regular: "Исходная"), Icon(id: "base-light", low: "светлая", regular: "Светлая"), Icon(id: "base-dark", low: "тёмная", regular: "Тёмная"), Icon(id: "base-cream", low: "кремовая", regular: "Кремовая"),
            Icon(id: "base-purple", low: "фиолетовая", regular: "Фиолетовая"), Icon(id: "base-blue", low: "голубая", regular: "Голубая"), Icon(id: "base-pink", low: "розовая", regular: "Розовая"), Icon(id: "base-red-neon", low: "красный неон", regular: "Красный неон")]),
        IconSet(id: "sonic", low: "sonic", regular: "Sonic", icons: ["Sonic", "Tails", "Knuckles", "Amy", "Shadow"].map { Icon(id: "sonic-" + $0.lowercased(), low: $0, regular: $0) }),
        IconSet(id: "kitty", low: "hello kitty", regular: "Hello Kitty", icons: ["Hello Kitty", "Kuromi", "My Melody", "Cinnamoroll", "Pompompurin"].map { Icon(id: "kitty-" + $0.lowercased().replacingOccurrences(of: " ", with: "-"), low: $0, regular: $0) }),
        IconSet(id: "pony", low: "my little pony", regular: "My Little Pony", icons: ["Twilight Sparkle", "Rainbow Dash", "Pinkie Pie", "Rarity", "Applejack", "Fluttershy"].map { Icon(id: "pony-" + $0.lowercased().replacingOccurrences(of: " ", with: "-"), low: $0, regular: $0) }),
    ]
    static func url(_ id: String) -> URL? { Bundle.main.url(forResource: id, withExtension: "heic", subdirectory: "AppIcons") }
    /// The standard choice (nil) is set explicitly from its file too. Falling back to the bundle icon showed the
    /// previous build's icon, which macOS keeps in its icon cache for the same bundle. Only a build without the pack
    /// falls back to the bundle icon.
    static func image(_ id: String?) -> NSImage? { url(id ?? standard).flatMap { NSImage(contentsOf: $0) } }
    static func apply(_ id: String?) {
        NSApp.applicationIconImage = image(id)
    }
    /// Tells the Dock tile plug-in (Sources/MicaDockTile/MicaDockTile.swift) the choice. It draws it on the tile of a quit
    /// mica and sets it as the Finder icon of the bundle (Finder, Launchpad, Spotlight, the Dock at launch). mica cannot
    /// write the bundle itself: a sandboxed write quarantines it. Sent at launch too, because an install or update
    /// replaces the bundle and the plug-in may have missed a change while the Dock was not running it.
    /// QA runs (the UI tour flips icons) leave the bundle alone.
    static func announce(_ id: String?) {
        guard !ProcessInfo.processInfo.arguments.contains("--qa") else { return }
        let message = DockIcon.message(icon: id, bundle: Bundle.main.bundlePath)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(DockIcon.notification), object: message, userInfo: nil, deliverImmediately: true)
    }
    private static var thumbnails: [String: NSImage] = [:]
    /// Small decoded copies for the picker, so it never holds 24 full-size images.
    static func thumbnail(_ id: String?) -> NSImage? {
        let key = id ?? "bundle"
        if let cached = thumbnails[key] { return cached }
        let image: NSImage?
        if let id {
            guard let url = url(id), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 112] as CFDictionary) else { return nil }
            image = NSImage(cgImage: cg, size: NSSize(width: 56, height: 56))
        } else {
            image = Bundle.main.image(forResource: "mica")
        }
        thumbnails[key] = image
        return image
    }
    static var available: Bool { url("base-original") != nil }
}
