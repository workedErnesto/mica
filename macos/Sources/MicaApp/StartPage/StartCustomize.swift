import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Start page block geometry. Tiles sit centred in 88 pt columns, so a 60 pt icon is inset 14 pt; block titles and
/// their controls use the same inset, and the customizing outline adds only vertical padding, so its left, right
/// and top insets all come to 14 pt and the blocks do not shift sideways when customizing starts.
enum StartLayout {
    static let column: CGFloat = 88
    static let inset: CGFloat = (column - 60) / 2
}

/// A block of the start page while customizing: a dashed outline. Its radius is concentric with the 20 pt switch
/// in the header corner, 14 pt inside it.
struct StartEditFrame: ViewModifier {
    let editing: Bool
    func body(content: Content) -> some View {
        content
            .padding(.vertical, editing ? Space.normal : 0)
            .background {
                if editing {
                    RoundedRectangle(cornerRadius: 10 + StartLayout.inset, style: .continuous)
                        .strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .transition(.opacity)
                }
            }
    }
}

/// Title row of a start page block. While customizing it carries the block's controls on the right: optional
/// order buttons and a switch that shows or hides the block. The row itself never dims, only the block content.
struct StartBlockHeader<Order: View>: View {
    let title: String
    let editing: Bool
    @Binding var shown: Bool
    @ObservedObject var store: Store
    @ViewBuilder var order: Order
    var body: some View {
        HStack(spacing: Space.small) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text3)
            Spacer(minLength: 0)
            if editing {
                HStack(spacing: Space.small) {
                    order
                    BareSwitch(label: store.text("показывать", "Показывать") + ": " + title, isOn: $shown)
                }
                .transition(.opacity)
            }
        }
        .frame(minHeight: 24)
        .padding(.horizontal, StartLayout.inset)
    }
}

extension StartBlockHeader where Order == EmptyView {
    init(title: String, editing: Bool, shown: Binding<Bool>, store: Store) {
        self.init(title: title, editing: editing, shown: shown, store: store) { EmptyView() }
    }
}

/// Quiet entry to customizing, in the corner of the start page.
struct StartCustomizeButton: View {
    @ObservedObject var store: Store
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11.5, weight: .medium))
                Text(store.text("настроить", "Настроить")).font(.system(size: 12))
            }
            .foregroundStyle(hover ? Palette.ink : Palette.text3)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .help(store.text("настроить начальную страницу", "Настроить начальную страницу"))
    }
}

/// Options that apply to the whole start page, under the live page while customizing.
struct StartCustomizeBar: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        let start = browser.prefs.start
        let defaults = StartPage()
        let changed = start.sections != defaults.sections || start.wordmark != defaults.wordmark || start.frequentCount != defaults.frequentCount
        HStack(spacing: Space.small) {
            Text(store.text("сайтов в разделе", "Сайтов в разделе"))
                .font(.system(size: 12)).foregroundStyle(Palette.text2).fixedSize()
            Segmented(selection: $browser.prefs.start.frequentCount, options: StartPage.frequentChoices.map { ($0, String($0)) }, compact: true, label: store.text("сайтов в разделе", "Сайтов в разделе"))
            Spacer(minLength: Space.small)
            IconButton(symbol: "arrow.counterclockwise", label: store.text("вернуть как было", "Вернуть как было"), size: 28) {
                withMotion(Motion.quick) {
                    browser.prefs.start.sections = defaults.sections
                    browser.prefs.start.wordmark = defaults.wordmark
                    browser.prefs.start.frequentCount = defaults.frequentCount
                }
            }.disabled(!changed)
            IconButton(symbol: "gearshape", label: store.text("все настройки", "Все настройки"), size: 28) {
                browser.customizingStart = false; browser.settingsSection = .start; browser.showSettings = true
            }
            done
        }
        .padding(.horizontal, Space.normal).padding(.vertical, 8)
        .frame(maxWidth: 520)
        .modifier(RaisedSurface(radius: Radius.panel))
    }
    private var done: some View {
        Button(store.text("готово", "Готово")) { withMotion(Motion.panel) { browser.customizingStart = false } }
            .buttonStyle(MButtonStyle(kind: .primary, compact: true)).keyboardShortcut(.defaultAction).fixedSize()
    }
}
