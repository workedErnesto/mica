import AppKit
import SwiftUI
import WebKit
import Combine
import MicaCore

@main
struct MicaMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
