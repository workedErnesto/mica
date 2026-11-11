import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct LayoutPicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $browser.prefs.layout, options: [(.left, browser.text("слева", "Слева")), (.top, browser.text("под адресом", "Под адресом")), (.tabsAbove, browser.text("над адресом", "Над адресом")), (.right, browser.text("справа", "Справа"))], symbols: ["sidebar.left", "rectangle.topthird.inset.filled", "macwindow", "sidebar.right"], width: width, label: browser.text("вкладки", "Вкладки"))
    }
}

struct ThemePicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $browser.prefs.theme, options: [(.system, browser.text("системная", "Системная")), (.light, browser.text("светлая", "Светлая")), (.dark, browser.text("тёмная", "Тёмная")), (.custom, browser.text("кастом", "Кастом"))], width: width, label: browser.text("тема", "Тема"))
    }
}

/// Each option is written in the style it selects.
struct CasePicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        let english = browser.prefs.language == .en
        Segmented(selection: $browser.prefs.lowercase, options: [(true, english ? "lowercase" : "со строчной"), (false, english ? "Standard" : "Обычный")], width: width, label: browser.text("текст интерфейса", "Текст интерфейса"))
    }
}

/// Language names are written in their own language.
struct LanguagePicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $browser.prefs.language, options: [(.ru, browser.prefs.lowercase ? "русский" : "Русский"), (.en, browser.prefs.lowercase ? "english" : "English")], width: width, label: browser.text("язык", "Язык"))
    }
}

/// Name for the start page greeting, with the option not to be addressed by name.
struct NameSettingRows: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        SettingRow(title: browser.text("имя", "Имя"), detail: browser.text("для приветствия на начальной странице", "Для приветствия на начальной странице")) {
            MTextField(placeholder: browser.text("как к вам обращаться", "Как к вам обращаться"), text: Binding(get: { browser.prefs.userName }, set: { browser.prefs.userName = String($0.prefix(Preferences.nameLimit)) }), symbol: "person")
                .frame(width: 220)
                .disabled(!browser.prefs.greetByName)
        }
        Toggle(browser.text("не обращаться по имени", "Не обращаться по имени"), isOn: Binding(get: { !browser.prefs.greetByName }, set: { value in withMotion(Motion.quick) { browser.prefs.greetByName = !value } })).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
    }
}

struct SearchPicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @Namespace private var space
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
            ForEach(SearchEngine.allCases, id: \.self) { engine in
                EngineChoice(title: engine.title(browser.prefs.language), host: URL(string: engine.home)?.host, selected: store.preferences.search == engine, namespace: space) {
                    withMotion(Motion.quick) { store.preferences.search = engine }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(browser.text("поисковик", "Поисковик"))
    }
}

struct EngineChoice: View {
    let title: String
    let host: String?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Monogram(host: host, size: 20)
                Text(title).font(.system(size: 12.5, weight: selected ? .medium : .regular)).foregroundStyle(selected ? Palette.ink : Palette.text2).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.ink).transition(Motion.pop) }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover && !selected ? Palette.hover : Palette.track)
                if selected { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.focusRing, lineWidth: 1.5).matchedGeometryEffect(id: "engine", in: namespace) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
