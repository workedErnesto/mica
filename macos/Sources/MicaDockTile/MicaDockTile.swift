import AppKit

/// Dock tile plug-in: keeps the icon chosen in mica's settings everywhere the system shows mica, not only while it runs.
///
/// The Dock loads it from Contents/PlugIns into its unsandboxed host (com.apple.dock.external.extra) for as long as mica
/// has a tile: while it runs and while it is kept in the Dock after quitting. It does two things:
/// 1. Draws the chosen icon on the tile of a quit mica. While mica runs, `NSApp.applicationIconImage` takes over.
/// 2. Sets the same icon as the Finder custom icon of mica's bundle, which Finder, Launchpad, Spotlight, the app
///    switcher and the Dock read before mica sets its own icon at launch. mica cannot do this itself: a write from
///    the sandbox puts a hard sandbox quarantine (0086) on the bundle that the sandbox cannot remove, and Gatekeeper
///    would then check this not notarized bundle at the next launch. A write from this host leaves no quarantine.
///    The custom icon (an `Icon\r` file and Finder info at the bundle root) fails only `codesign --verify --strict`;
///    plain verification, SecCodeCheckValidity and launching are unaffected. scripts/install.sh verifies the new
///    bundle before it gets an icon, and this plug-in sets the icon again on the next load.
///
/// mica's preferences are out of reach (the data container of a sandboxed app is closed to other processes since
/// macOS 14), so mica posts its choice in a distributed notification (DockIcon in MicaCore, compiled into this
/// plug-in), and the plug-in remembers it in its own defaults domain for the next Dock start.
@objc(MicaDockTile)
final class MicaDockTile: NSObject, NSDockTilePlugIn {
    private static let defaults = UserDefaults(suiteName: "app.mica.browser.docktile")
    private static let writer = DispatchQueue(label: "app.mica.browser.docktile.bundle-icon", qos: .utility)
    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?
    private let app = Bundle(for: MicaDockTile.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var chosenKey: String { "icon " + app.path }
    private var appliedKey: String { "bundleIcon " + app.path }

    func setDockTile(_ dockTile: NSDockTile?) {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer); self.observer = nil }
        tile = dockTile
        guard dockTile != nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(DockIcon.notification), object: nil, queue: .main) { [weak self] note in
            guard let self, let message = note.object as? String, let id = DockIcon.icon(in: message, bundle: self.app.path) else { return }
            Self.defaults?.set(id, forKey: self.chosenKey)
            self.refresh()
        }
        refresh()
    }

    private var chosen: String? {
        guard let id = Self.defaults?.string(forKey: chosenKey), DockIcon.valid(id) else { return nil }
        return id
    }

    private func refresh() {
        guard let tile else { return }
        let id = chosen
        // The standard choice is drawn from its file too: the Dock may still hold the previous custom icon.
        if let id, let image = NSImage(contentsOf: iconURL(id)) {
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
        if let id { applyToBundle(id) }
    }

    private func iconURL(_ id: String) -> URL { app.appendingPathComponent("Contents/Resources/AppIcons/" + id + ".heic") }

    /// Writes only when the bundle differs from the choice: a replaced bundle (install, update) has no custom icon.
    private func applyToBundle(_ id: String) {
        let app = self.app, appliedKey = self.appliedKey, url = iconURL(id)
        Self.writer.async {
            let marker = app.appendingPathComponent("Icon\r").path
            let hasCustom = FileManager.default.fileExists(atPath: marker)
            let applied = Self.defaults?.string(forKey: appliedKey)
            if id == DockIcon.standard {
                guard hasCustom else { return }
                if NSWorkspace.shared.setIcon(nil, forFile: app.path, options: []) { Self.defaults?.removeObject(forKey: appliedKey) }
            } else {
                guard !hasCustom || applied != id, FileManager.default.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else { return }
                if NSWorkspace.shared.setIcon(image, forFile: app.path, options: []) { Self.defaults?.set(id, forKey: appliedKey) }
            }
        }
    }
}
