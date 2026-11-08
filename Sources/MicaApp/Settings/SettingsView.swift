import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let dismiss: () -> Void
    @Namespace private var selection
    private var section: SettingsSection { browser.settingsSection }
    var body: some View {
        GeometryReader { geo in
        let compact = geo.size.width < 720
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text(store.text("настройки", "Настройки")).font(.system(size: 20, weight: .regular)).tracking(-0.4).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, Space.normal)
                }
                ForEach(SettingsSection.allCases) { item in navItem(item, compact: compact) }
                Spacer()
                if compact {
                    IconButton(symbol: "xmark", label: store.text("готово", "Готово"), size: 36) { dismiss() }
                } else {
                    Button(store.text("готово", "Готово")) { dismiss() }.buttonStyle(MButtonStyle(kind: .primary, fill: true)).keyboardShortcut(.cancelAction)
                }
            }
            .padding(Space.normal)
            .frame(width: compact ? 60 : 228)
            .background(store.look.shell)
            Rectangle().fill(Palette.hairline).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    Text(section.title(store)).font(.system(size: 22, weight: .regular)).tracking(-0.5).foregroundStyle(Palette.ink)
                    content(height: geo.size.height)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(section)
                .transition(Motion.reduced ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
            }
            .scrollIndicators(.never)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if section == .about {
                    Text(store.text("develop whoa with ❤️", "Develop whoa with ❤️")).font(.system(size: 12)).foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 22).padding(.top, Space.small)
                        .transition(.opacity)
                }
            }
            .background(Palette.canvas)
        }
        .animation(Motion.quick, value: section)
        }
    }

    private func navItem(_ item: SettingsSection, compact: Bool) -> some View {
        NavItem(title: item.title(store), symbol: item.symbol, selected: section == item, namespace: selection, compact: compact) { withMotion(Motion.quick) { browser.settingsSection = item } }
    }

    @ViewBuilder private func content(height: CGFloat) -> some View {
        switch section {
        case .space: SpaceSettings(store: store, browser: browser, dismiss: dismiss)
        case .appearance: AppearanceSettings(store: store)
        case .start: StartSettings(store: store)
        case .search: SearchSettings(store: store, browser: browser)
        case .session: SessionSettings(store: store)
        case .permissions: PermissionSettings(store: store)
        case .about: AboutSettings(store: store, browser: browser, dismiss: dismiss)
        }
    }
}
