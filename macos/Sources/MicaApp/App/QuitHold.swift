import AppKit
import SwiftUI

/// ⌘Q quits only after being held for `duration`, so a stray press does not close every window.
/// A local event monitor sees key events before the main menu, so the keyboard goes through the hold while
/// choosing "завершить mica" with the mouse still quits at once. Releasing Q or ⌘, pressing another key or
/// switching to another app cancels.
@MainActor
final class QuitHold: ObservableObject {
    static let shared = QuitHold()
    static let duration: TimeInterval = 2

    struct Session: Identifiable {
        let id = UUID()
        let window: ObjectIdentifier
        let start: Date
        let keyCode: UInt16
    }

    @Published private(set) var session: Session?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var deadline: Task<Void, Never>?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            MainActor.assumeIsolated { QuitHold.shared.swallows(event) } ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { QuitHold.shared.cancel() }
        }
    }

    /// ⌘Q with no other modifier. Layouts without Latin letters (Russian) report their own letter, so the physical
    /// Q key counts there, as it does for menu key equivalents.
    static func isQuit(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if key == "q" { return true }
        return event.keyCode == 12 && key.allSatisfy { !$0.isASCII }
    }

    /// Whether the event belongs to the hold and must not reach the menu or the page.
    private func swallows(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            if Self.isQuit(event) {
                if !event.isARepeat && session == nil { begin(keyCode: event.keyCode) }
                return true
            }
            if session != nil { cancel() }
            return false
        case .keyUp:
            guard let session, event.keyCode == session.keyCode else { return false }
            cancel()
            return true
        case .flagsChanged:
            if session != nil && !event.modifierFlags.contains(.command) { cancel() }
            return false
        default:
            return false
        }
    }

    private func begin(keyCode: UInt16) {
        guard let window = target() else { NSApp.terminate(nil); return }
        let session = Session(window: ObjectIdentifier(window), start: Date(), keyCode: keyCode)
        self.session = session
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            guard let self, !Task.isCancelled, self.session?.id == session.id else { return }
            self.session = nil
            self.deadline = nil
            // applicationShouldTerminate still asks about running downloads.
            NSApp.terminate(nil)
        }
    }

    func cancel() {
        deadline?.cancel()
        deadline = nil
        if session != nil { session = nil }
    }

    /// The key browser window, or the frontmost visible one when a panel of another kind has focus.
    private func target() -> NSWindow? {
        if let key = NSApp.keyWindow, key.windowController is BrowserWindow, key.isVisible { return key }
        return NSApp.orderedWindows.first { $0.windowController is BrowserWindow && $0.isVisible && !$0.isMiniaturized }
    }
}

/// Window overlay that shows the badge in the window the hold started in. It never takes clicks.
struct QuitHoldOverlay: View {
    @ObservedObject private var hold = QuitHold.shared
    let browser: BrowserModel
    let store: Store
    var body: some View {
        ZStack {
            if let session = hold.session, let window = browser.controller?.window, session.window == ObjectIdentifier(window) {
                QuitHoldBadge(session: session, store: store)
                    .id(session.id)
                    .transition(.asymmetric(insertion: Motion.pop, removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(Motion.reduced ? Motion.hover : Motion.snappySpring, value: hold.session?.id)
    }
}

/// Raised badge whose outline is drawn from the top centre clockwise over the hold time, so it reads as progress.
struct QuitHoldBadge: View {
    let session: QuitHold.Session
    let store: Store
    @Environment(\.look) private var look
    @State private var progress: Double
    private let line: CGFloat = 2

    init(session: QuitHold.Session, store: Store) {
        self.session = session
        self.store = store
        _progress = State(initialValue: min(1, Date().timeIntervalSince(session.start) / QuitHold.duration))
    }

    var body: some View {
        HStack(spacing: Space.small) {
            Text(store.text("закрытие mica", "Закрытие mica"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
            KeyHint(keys: "⌘Q")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .modifier(RaisedSurface())
        .overlay(HoldOutline(progress: progress, radius: Radius.panel, inset: line / 2).stroke(look.accent ?? Palette.ink, style: StrokeStyle(lineWidth: line, lineCap: .butt)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .onAppear {
            // The outline is the countdown itself, so it keeps running with Reduce Motion, like a progress bar.
            let remaining = max(0, QuitHold.duration - Date().timeIntervalSince(session.start))
            withAnimation(.linear(duration: remaining)) { progress = 1 }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var announcement: String { store.text("закрытие mica: отпустите клавиши, чтобы отменить", "Закрытие mica: отпустите клавиши, чтобы отменить") }
}

/// The badge's continuous rounded rectangle, trimmed from the top centre clockwise to `progress`.
/// SwiftUI's rounded rectangle path starts at the middle of the right edge and runs clockwise, so the top centre
/// sits at three quarters of its length for any size; the visible part is split across that seam.
struct HoldOutline: Shape {
    var progress: Double
    var radius: CGFloat
    var inset: CGFloat
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let full = RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
        let value = min(max(progress, 0), 1)
        guard value > 0 else { return Path() }
        var path = full.trimmedPath(from: 0.75, to: min(1, 0.75 + value))
        if value > 0.25 { path.addPath(full.trimmedPath(from: 0, to: value - 0.25)) }
        return path
    }
}
