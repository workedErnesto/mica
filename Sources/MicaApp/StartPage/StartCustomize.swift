import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// A part of the start page while customizing: a dashed outline, dimmed when hidden. With a title and an action
/// it also gets its own show or hide button (the wordmark); sections put theirs in the header.
struct StartEditFrame: ViewModifier {
    let editing: Bool
    let visible: Bool
    var title: String?
    @ObservedObject var store: Store
    var toggle: (() -> Void)?
    func body(content: Content) -> some View {
        content
            .opacity(editing && !visible ? 0.4 : 1)
            .padding(editing ? Space.normal : 0)
            .background {
                if editing {
                    RoundedRectangle(cornerRadius: Radius.panel + Space.normal - 4, style: .continuous)
                        .strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if editing, let title, let toggle {
                    IconButton(symbol: visible ? "eye" : "eye.slash", label: (visible ? store.text("скрыть", "Скрыть") : store.text("показать", "Показать")) + ": " + title, selected: !visible, size: 24) {
                        withMotion(Motion.quick) { toggle() }
                    }
                    .contentTransition(.symbolEffect(.replace))
                    .padding(4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: editing && title != nil ? .infinity : nil)
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
        let start = store.preferences.start
        let defaults = StartPage()
        let changed = start.sections != defaults.sections || start.wordmark != defaults.wordmark || start.frequentCount != defaults.frequentCount
        HStack(spacing: Space.small) {
            Text(store.text("сайтов в разделе", "Сайтов в разделе"))
                .font(.system(size: 12)).foregroundStyle(Palette.text2).fixedSize()
            Segmented(selection: $store.preferences.start.frequentCount, options: StartPage.frequentChoices.map { ($0, String($0)) }, compact: true, label: store.text("сайтов в разделе", "Сайтов в разделе"))
            Spacer(minLength: Space.small)
            IconButton(symbol: "arrow.counterclockwise", label: store.text("вернуть как было", "Вернуть как было"), size: 28) {
                withMotion(Motion.quick) {
                    store.preferences.start.sections = defaults.sections
                    store.preferences.start.wordmark = defaults.wordmark
                    store.preferences.start.frequentCount = defaults.frequentCount
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
