import AppKit
import SwiftUI
import MicaCore

/// Profiles as a gallery of cards and the editor of the chosen one: name, icon, background and glyph colour.
/// The look itself is edited in the window of the profile, in the space, appearance and start page sections.
struct ProfileSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @Namespace private var selection
    var body: some View {
        let editing = store.profile(browser.editingProfile ?? browser.profileID)
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.small) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 180), spacing: Space.small)], alignment: .leading, spacing: Space.small) {
                    ForEach(store.profiles) { profile in
                        ProfileCard(profile: profile, selected: profile.id == editing.id, namespace: selection, store: store, browser: browser) {
                            withMotion(Motion.quick) { browser.editingProfile = profile.id }
                        }
                        .transition(Motion.pop)
                    }
                    if store.profiles.count < Profiles.limit {
                        NewProfileCard(store: store, browser: browser) {
                            let profile = store.addProfile(from: browser.profileID)
                            withMotion(Motion.quick) { browser.editingProfile = profile.id }
                        }
                    }
                }
                .animation(Motion.quick, value: store.profiles.map(\.id))
                Text(browser.text("пароли, cookie, история, закладки, загрузки и расширения общие для всех профилей. профиль меняет начальную страницу, расположение вкладок и кнопок, тему, цвета, язык и регистр текста, обращение и закреплённые вкладки. в истории видно, в каком профиле открыта страница.", "Пароли, cookie, история, закладки, загрузки и расширения общие для всех профилей. Профиль меняет начальную страницу, расположение вкладок и кнопок, тему, цвета, язык и регистр текста, обращение и закреплённые вкладки. В истории видно, в каком профиле открыта страница."))
                    .font(.system(size: 11.5)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            SettingsGroup(footnote: browser.text("в этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля. в новом окне откроется окно профиля или выйдет вперёд уже открытое. в Доке и строке меню профиль всегда открывается своим окном.", "В этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля. В новом окне откроется окно профиля или выйдет вперёд уже открытое. В Доке и строке меню профиль всегда открывается своим окном.")) {
                SettingRow(title: browser.text("профиль из меню открывать", "Профиль из меню открывать"), divider: false) {
                    Segmented(selection: $store.preferences.profileOpening, options: [(.ask, browser.text("спрашивать", "Спрашивать")), (.here, browser.text("в этом окне", "В этом окне")), (.newWindow, browser.text("в новом окне", "В новом окне"))], width: 340, label: browser.text("профиль из меню открывать", "Профиль из меню открывать"))
                }
            }
            ProfileEditor(profile: editing, store: store, browser: browser)
                .id(editing.id)
                .transition(Motion.reduced ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
        }
        .animation(Motion.quick, value: editing.id)
    }
}

/// What a profile is doing right now, shown under its name.
@MainActor
private func status(_ profile: Profile, store: Store, browser: BrowserModel) -> String {
    if browser.profileID == profile.id { return browser.text("это окно", "Это окно") }
    if store.windows.contains(where: { $0.model.profileID == profile.id && !$0.model.privateMode }) { return browser.text("открыт в другом окне", "Открыт в другом окне") }
    return profile.isStandard ? browser.text("основной", "Основной") : browser.text("не открыт", "Не открыт")
}

/// One profile in the gallery: its mark, name and status. The selection ring moves between cards.
private struct ProfileCard: View {
    let profile: Profile
    let selected: Bool
    let namespace: Namespace.ID
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let action: () -> Void
    @State private var hover = false
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous)
        Button(action: action) {
            VStack(spacing: Space.small) {
                ProfileMark(profile: profile, size: 44)
                    .scaleEffect(hover && !reduced ? 1.06 : 1)
                    .shadow(color: Color(hex: profile.background).opacity(hover || selected ? 0.35 : 0), radius: 8, y: 3)
                VStack(spacing: 1) {
                    Text(browser.profileName(profile)).font(.system(size: 12.5, weight: selected ? .medium : .regular)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(status(profile, store: store, browser: browser)).font(.system(size: 11)).foregroundStyle(Palette.text3).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background {
                shape.fill(hover && !selected ? Palette.hover : Palette.surface)
                shape.strokeBorder(Palette.hairline, lineWidth: 1)
                if selected { shape.strokeBorder(look.focus, lineWidth: 2).matchedGeometryEffect(id: "profile", in: namespace) }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .overlay(alignment: .topTrailing) {
            if hover {
                MenuButton(label: browser.text("действия", "Действия"), size: 22) { ProfileActions.entries(profile, store: store, browser: browser) }
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .micaContextMenu { ProfileActions.entries(profile, store: store, browser: browser) }
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .help(browser.profileName(profile))
        .accessibilityLabel(browser.profileName(profile) + ", " + status(profile, store: store, browser: browser))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NewProfileCard: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous)
        Button(action: action) {
            VStack(spacing: Space.small) {
                Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(hover ? Palette.ink : Palette.text2)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 44 * 0.3, style: .continuous).strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .scaleEffect(hover && !reduced ? 1.06 : 1)
                VStack(spacing: 1) {
                    Text(browser.text("новый профиль", "Новый профиль")).font(.system(size: 12.5)).foregroundStyle(hover ? Palette.ink : Palette.text2).lineLimit(1)
                    Text(browser.text("вид этого окна", "Вид этого окна")).font(.system(size: 11)).foregroundStyle(Palette.text3).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background { shape.fill(hover ? Palette.hover : .clear); shape.strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .accessibilityLabel(browser.text("новый профиль", "Новый профиль"))
    }
}

/// Actions on a profile, shared by the gallery card and the editor.
@MainActor
enum ProfileActions {
    static func entries(_ profile: Profile, store: Store, browser: BrowserModel) -> [MenuEntry] {
        [
            .item(browser.text("открыть в новом окне", "Открыть в новом окне"), symbol: "macwindow.badge.plus") { store.openProfile(profile.id, newWindow: true) },
            .item(browser.text("открыть в этом окне", "Открыть в этом окне"), symbol: "macwindow") { withMotion(Motion.panel) { browser.switchProfile(to: profile.id) } }
                .with(enabled: browser.profileID != profile.id),
            .divider,
            .item(browser.text("удалить профиль…", "Удалить профиль…"), symbol: "trash", destructive: true) { Task { await remove(profile, store: store, browser: browser) } }
                .with(enabled: !profile.isStandard),
        ]
    }
    static func remove(_ profile: Profile, store: Store, browser: BrowserModel) async {
        let name = browser.profileName(profile)
        let answer = await ask(title: browser.text("удалить профиль ", "Удалить профиль ") + browser.quoted(name) + "?", detail: browser.text("его окна перейдут в обычный профиль, закреплённые вкладки профиля закроются. пароли, история и закладки останутся.", "Его окна перейдут в обычный профиль, закреплённые вкладки профиля закроются. Пароли, история и закладки останутся."), buttons: [browser.text("отмена", "Отмена"), browser.text("удалить", "Удалить")], window: browser.controller?.window)
        guard answer == 1 else { return }
        withMotion(Motion.quick) {
            if browser.editingProfile == profile.id { browser.editingProfile = nil }
            store.removeProfile(profile.id)
        }
    }
}

/// Name, mark and actions of one profile above its icon, background and glyph colour. Every change applies at once.
private struct ProfileEditor: View {
    let profile: Profile
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var name: String
    @Namespace private var iconSelection
    @Environment(\.accessibilityReduceMotion) private var reduced
    init(profile: Profile, store: Store, browser: BrowserModel) {
        self.profile = profile; self.store = store; self.browser = browser
        _name = State(initialValue: profile.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            hero
            SettingsGroup(title: browser.text("значок", "Значок"), footnote: footnote) {
                VStack(alignment: .leading, spacing: Space.small) {
                    Text(browser.text("иконка", "Иконка")).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 42), spacing: 4)], alignment: .leading, spacing: 4) {
                        ForEach(Array(ProfileCatalog.icons.enumerated()), id: \.element) { index, icon in
                            ProfileIconChoice(icon: icon, index: index, profile: profile, selected: profile.icon == icon, namespace: iconSelection) {
                                withMotion(Motion.quick) { store.updateProfile(profile.id) { $0.icon = icon } }
                            }
                        }
                    }
                }
                .padding(14)
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
                SettingRow(title: browser.text("фон", "Фон")) {
                    HStack(spacing: 2) {
                        ForEach(ProfileCatalog.backgrounds, id: \.self) { hex in
                            ColorDot(hex: hex, selected: profile.background == hex, size: 24) { withMotion(Motion.quick) { store.updateProfile(profile.id) { $0.background = hex } } }
                        }
                        ColorWell(hex: profile.background, presets: ProfileCatalog.backgrounds, label: browser.text("другой цвет", "Другой цвет"), size: 24) { hex in
                            store.updateProfile(profile.id) { $0.background = hex }
                        }
                    }
                }
                SettingRow(title: browser.text("цвет значка", "Цвет значка"), detail: browser.text("авто берёт читаемый на фоне", "Авто берёт читаемый на фоне"), divider: false) {
                    Segmented(selection: Binding(get: { profile.glyph }, set: { value in store.updateProfile(profile.id) { $0.glyph = value } }),
                              options: [(.auto, browser.text("авто", "Авто")), (.light, browser.text("белый", "Белый")), (.dark, browser.text("чёрный", "Чёрный"))],
                              width: 240, label: browser.text("цвет значка", "Цвет значка"))
                }
            }
        }
    }

    /// The profile at a glance: a large mark on a wash of its own colour, the name field and what can be done with it.
    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous)
        return HStack(alignment: .center, spacing: 18) {
            ProfileMark(profile: profile, size: 72)
                .shadow(color: Color(hex: profile.background).opacity(0.4), radius: 14, y: 6)
                .id(profile.icon)
                .transition(reduced ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            VStack(alignment: .leading, spacing: Space.small) {
                MTextField(placeholder: profile.isStandard ? browser.profileName(Profile.standard()) : browser.text("название профиля", "Название профиля"), text: $name, prominent: true)
                    .frame(maxWidth: 300)
                    .onChange(of: name) { _, value in
                        // Another profile keeps its last name while the field is empty; the standard one falls back to its default.
                        store.updateProfile(profile.id) { $0.name = value }
                    }
                    .accessibilityLabel(browser.text("название профиля", "Название профиля"))
                HStack(spacing: Space.small) {
                    if profile.id != browser.profileID {
                        Button(browser.text("переключить это окно", "Переключить это окно")) { withMotion(Motion.panel) { browser.switchProfile(to: profile.id) } }
                            .buttonStyle(MButtonStyle(kind: .primary, compact: true))
                    } else {
                        Label(browser.text("это окно", "Это окно"), systemImage: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: Radius.icon - 1, style: .continuous).fill(Palette.surface.opacity(0.7)))
                    }
                    Button(browser.text("открыть в новом окне", "Открыть в новом окне")) { store.openProfile(profile.id, newWindow: true) }
                        .buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                    if !profile.isStandard {
                        IconButton(symbol: "trash", label: browser.text("удалить профиль…", "Удалить профиль…"), size: 26) { Task { await ProfileActions.remove(profile, store: store, browser: browser) } }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            shape.fill(Palette.surface)
            shape.fill(Color(hex: profile.background).opacity(0.1))
            shape.strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .animation(Motion.quick, value: profile.icon)
        .animation(Motion.hover, value: profile.background)
    }

    private var footnote: String {
        profile.id == browser.profileID
            ? browser.text("раскладка, оформление и начальная страница этого окна сохраняются в этот профиль.", "Раскладка, оформление и начальная страница этого окна сохраняются в этот профиль.")
            : browser.text("раскладку, оформление и начальную страницу профиля настраивают в его окне.", "Раскладку, оформление и начальную страницу профиля настраивают в его окне.")
    }
}

/// One icon of the pack drawn in the profile's own colours; the selection ring moves to the chosen one.
private struct ProfileIconChoice: View {
    let icon: String
    let index: Int
    let profile: Profile
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            ProfileMark(icon: icon, background: profile.background, glyph: profile.glyph, size: 30)
                .scaleEffect(hover && !reduced ? 1.08 : 1)
                .padding(4)
                .background {
                    if selected { shape.strokeBorder(look.focus, lineWidth: 2).matchedGeometryEffect(id: "icon", in: namespace) }
                    else if hover { shape.fill(Palette.hover) }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .accessibilityLabel(Store.shared.text("иконка ", "Иконка ") + String(index + 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
