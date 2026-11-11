import AppKit
import SwiftUI
import MicaCore

/// Source browser, what to bring, and the result. Shared by onboarding and settings.
struct ImportView: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @ObservedObject var manager: ImportManager
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            if !manager.discovered {
                HStack(spacing: Space.small) { ProgressView().controlSize(.small); Text(browser.text("ищем браузеры на этом Mac", "Ищем браузеры на этом Mac")).font(.system(size: 12.5)).foregroundStyle(Palette.text2) }
                    .padding(.vertical, Space.small)
            } else if manager.profiles.isEmpty {
                Text(browser.text("доступные профили не найдены. можно выбрать папку профиля или файл экспорта", "Доступные профили не найдены. Можно выбрать папку профиля или файл экспорта"))
                    .font(.system(size: 12.5)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
            } else {
                SettingsGroup(title: browser.text("откуда", "Откуда")) {
                    ForEach(Array(manager.profiles.enumerated()), id: \.element.id) { index, profile in
                        SourceRow(store: store, browser: browser, manager: manager, profile: profile, divider: index < manager.profiles.count - 1)
                    }
                }
                if manager.selected == nil {
                    Text(browser.text("выберите браузер, чтобы открыть его данные", "Выберите браузер, чтобы открыть его данные"))
                        .font(.system(size: 12.5)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
                } else if manager.selected?.browser.family == .safari && manager.safariLocked {
                    safariHelp
                } else if manager.selected != nil {
                    SettingsGroup(title: browser.text("что перенести", "Что перенести"), footnote: browser.text("входы на сайты и пароли не переносятся. исходный браузер не изменяется", "Входы на сайты и пароли не переносятся. Исходный браузер не изменяется")) {
                        kindToggle(.history, browser.text("история", "История"), divider: true)
                        kindToggle(.bookmarks, browser.text("закладки и избранное", "Закладки и избранное"), divider: false)
                    }
                }
            }
            HStack(spacing: Space.small) {
                if manager.selected != nil && !manager.selectedNeedsAccess && !(manager.selected?.browser.family == .safari && manager.safariLocked) {
                    Button(browser.text("перенести", "Перенести")) { manager.run() }
                        .buttonStyle(MButtonStyle(kind: .primary))
                        .disabled(manager.phase == .reading || manager.kinds.intersection(manager.selected?.browser.kinds ?? []).isEmpty)
                }
                OtherImportSources(store: store, browser: browser, manager: manager)
                if manager.phase == .reading { ProgressView().controlSize(.small).transition(.opacity) }
            }
            result
        }
        .onAppear { if !manager.discovered { manager.discover() } }
        .animation(Motion.quick, value: manager.selection)
        .animation(Motion.quick, value: manager.phase)
    }

    private func kindToggle(_ kind: ImportKind, _ title: String, divider: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { manager.kinds.contains(kind) }, set: { on in if on { manager.kinds.insert(kind) } else { manager.kinds.remove(kind) } }))
        .toggleStyle(MToggleStyle()).modifier(RowInset(divider: divider))
    }

    private var safariHelp: some View {
        SettingsGroup(title: "Safari") {
            VStack(alignment: .leading, spacing: Space.small) {
                Text(browser.text("macOS ограничивает доступ к файлам Safari. экспортируйте данные в Safari: «Файл», «Экспортировать», «Данные браузера в файл», затем выберите архив здесь", "macOS ограничивает доступ к файлам Safari. Экспортируйте данные в Safari: «Файл», «Экспортировать», «Данные браузера в файл», затем выберите архив здесь"))
                    .font(.system(size: 12.5)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    @ViewBuilder private var result: some View {
        switch manager.phase {
        case .done(let summary):
            VStack(alignment: .leading, spacing: 4) {
                Text(browser.text("готово: ", "Готово: ") + summary.source).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                Text(counts(summary)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Palette.text2)
                ForEach(summary.problems, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true) }
            }
            .transition(Motion.pop)
        case .failed(let message):
            Text(message).font(.system(size: 12.5)).foregroundStyle(Palette.danger).transition(.opacity)
        default: EmptyView()
        }
    }

    private func counts(_ s: ImportManager.Summary) -> String {
        browser.text("история: ", "История: ") + "\(s.history), " + browser.text("закладки: ", "Закладки: ") + "\(s.bookmarks)"
    }
}

/// One browser profile: the app's own icon, its name and the profile, a check when chosen.
private struct SourceRow: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @ObservedObject var manager: ImportManager
    let profile: ImportProfile
    let divider: Bool
    @State private var hover = false
    private var chosen: Bool { manager.selection == profile.id }
    var body: some View {
        VStack(spacing: 0) {
            Button { manager.select(profile) } label: {
                HStack(spacing: 10) {
                    Image(nsImage: Self.icon(profile.browser.bundleID)).resizable().interpolation(.high).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(manager.title(profile)).font(.system(size: 13)).foregroundStyle(Palette.ink)
                        if !profile.name.isEmpty, manager.profiles.filter({ $0.browser == profile.browser }).count > 1 {
                            Text(profile.name).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                        .opacity(chosen ? 1 : 0).scaleEffect(chosen || Motion.reduced ? 1 : 0.6)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Palette.hover : .clear).padding(3))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .disabled(manager.phase == .reading)
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            if divider { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 46) }
        }
    }

    static func icon(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }
}

/// Less common inputs stay together, beside the main import action.
private struct OtherImportSources: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @ObservedObject var manager: ImportManager
    @State private var anchor = PopupAnchor()

    var body: some View {
        Button(browser.text("другие источники…", "Другие источники…")) {
            guard let view = anchor.view, let window = view.window else { return }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            MicaMenu.shared.show([
                .item(browser.text("выбрать папку профиля…", "Выбрать папку профиля…")) { manager.chooseProfile() },
                .item(browser.text("из файла экспорта…", "Из файла экспорта…")) { manager.chooseExport() }
            ], below: rect, in: window)
        }
        .buttonStyle(MButtonStyle(kind: .secondary))
        .disabled(manager.phase == .reading)
        .background(PopupAnchorView(anchor: anchor))
    }
}
