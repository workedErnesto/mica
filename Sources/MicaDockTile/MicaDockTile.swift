import AppKit

/// Dock tile plug-in: while mica is quit but kept in the Dock, the Dock shows the icon chosen in mica's settings.
/// The Dock loads it from Contents/PlugIns; it reads only the `appIcon` field of mica's preferences file and the
/// icon files inside the same app bundle. While mica runs, `NSApp.applicationIconImage` takes over.
@objc(MicaDockTile)
final class MicaDockTile: NSObject, NSDockTilePlugIn {
    static let changed = Notification.Name("app.mica.browser.appIconChanged")
    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?

    func setDockTile(_ dockTile: NSDockTile?) {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer); self.observer = nil }
        tile = dockTile
        guard dockTile != nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        guard let tile else { return }
        if let id = chosenIcon(), let url = iconURL(id), let image = NSImage(contentsOf: url) {
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }

    private func chosenIcon() -> String? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let file = URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Library/Containers/app.mica.browser/Data/Library/Application Support/mica/preferences.json")
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["appIcon"] as? String
    }

    private func iconURL(_ id: String) -> URL? {
        guard id.range(of: "^[a-z0-9-]{1,64}$", options: .regularExpression) != nil else { return nil }
        let contents = Bundle(for: MicaDockTile.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let url = contents.appendingPathComponent("Resources/AppIcons/" + id + ".heic")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
