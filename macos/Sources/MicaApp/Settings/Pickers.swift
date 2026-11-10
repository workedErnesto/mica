import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct LayoutPicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $browser.prefs.layout, options: [(.left, store.text("слева", "Слева")), (.top, store.text("под адресом", "Под адресом")), (.tabsAbove, store.text("над адресом", "Над адресом")), (.right, store.text("справа", "Справа"))], symbols: ["sidebar.left", "rectangle.topthird.inset.filled", "macwindow", "sidebar.right"], width: width, label: store.text("вкладки", "Вкладки"))
    }
}

struct ThemePicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $browser.prefs.theme, options: [(.system, store.text("системная", "Системная")), (.light, store.text("светлая", "Светлая")), (.dark, store.text("тёмная", "Тёмная")), (.custom, store.text("кастом", "Кастом"))], width: width, label: store.text("тема", "Тема"))
    }
}

/// Each option is written in the style it selects.
struct CasePicker: View {
    @ObservedObject var store: Store
    var width: CGFloat = 0
    var body: some View {
        let english = store.preferences.language == .en
        Segmented(selection: $store.preferences.lowercase, options: [(true, english ? "lowercase" : "со строчной"), (false, english ? "Standard" : "Обычный")], width: width, label: store.text("текст интерфейса", "Текст интерфейса"))
    }
}

/// Language names are written in their own language.
struct LanguagePicker: View {
    @ObservedObject var store: Store
    var width: CGFloat = 0
    var body: some View {
        Segmented(selection: $store.preferences.language, options: [(.ru, store.preferences.lowercase ? "русский" : "Русский"), (.en, store.preferences.lowercase ? "english" : "English")], width: width, label: store.text("язык", "Язык"))
    }
}

/// Name for the start page greeting, with the option not to be addressed by name.
struct NameSettingRows: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        SettingRow(title: store.text("имя", "Имя"), detail: store.text("для приветствия на начальной странице", "Для приветствия на начальной странице")) {
            MTextField(placeholder: store.text("как к вам обращаться", "Как к вам обращаться"), text: Binding(get: { browser.prefs.userName }, set: { browser.prefs.userName = String($0.prefix(Preferences.nameLimit)) }), symbol: "person")
                .frame(width: 220)
                .disabled(!browser.prefs.greetByName)
        }
        Toggle(store.text("не обращаться по имени", "Не обращаться по имени"), isOn: Binding(get: { !browser.prefs.greetByName }, set: { value in withMotion(Motion.quick) { browser.prefs.greetByName = !value } })).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
    }
}

struct SearchPicker: View {
    @ObservedObject var store: Store
    @Namespace private var space
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
            ForEach(SearchEngine.allCases, id: \.self) { engine in
                EngineChoice(title: engine.title(store.preferences.language), host: URL(string: engine.home)?.host, selected: store.preferences.search == engine, namespace: space) {
                    withMotion(Motion.quick) { store.preferences.search = engine }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.text("поисковик", "Поисковик"))
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
