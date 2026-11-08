import AppKit
import UserNotifications
import MicaCore

/// System side of web notifications: authorization, delivery, clicks and dismissals.
/// Only pages in normal windows with a saved "allow" decision reach it; the bridge checks that first.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    unowned let store: Store
    private let center = UNUserNotificationCenter.current()
    static let category = "mica.web"
    init(store: Store) {
        self.store = store
        super.init()
    }
    /// Called at launch, before any notification can be clicked, so a click that opens mica is still delivered.
    func start() {
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: [], options: [.customDismissAction])])
    }
    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    /// Asks macOS once; afterwards the answer lives in System Settings and mica only reads it.
    func authorize() async -> Bool {
        switch await status() {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }
    func show(_ notification: WebNotification, origin: String, tab: Tab) async -> String? {
        guard await authorize() else { return nil }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = URL(string: origin)?.host ?? origin
        content.body = notification.body
        content.sound = notification.silent ? nil : .default
        content.threadIdentifier = origin
        content.categoryIdentifier = Self.category
        content.userInfo = ["tab": tab.id.uuidString, "id": notification.id, "origin": origin]
        let identifier = NotificationPolicy.identifier(origin: origin, tab: tab.id, notification: notification)
        do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)); return identifier }
        catch { return nil }
    }
    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let tabID = (info["tab"] as? String).flatMap(UUID.init(uuidString:)), let id = info["id"] as? String else { return }
        let dismissed = response.actionIdentifier == UNNotificationDismissActionIdentifier
        await MainActor.run { self.deliver(tab: tabID, id: id, dismissed: dismissed) }
    }
    private func deliver(tab tabID: UUID, id: String, dismissed: Bool) {
        // The page may be gone; then a click only brings mica forward.
        guard let controller = store.windows.first(where: { $0.model.tabs.contains { $0.id == tabID } }),
              let tab = controller.model.tabs.first(where: { $0.id == tabID }) else {
            if !dismissed { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        if !dismissed {
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.model.select(tab)
        }
        NotificationBridge.dispatch(tab, id: id, event: dismissed ? "close" : "click")
    }
}
