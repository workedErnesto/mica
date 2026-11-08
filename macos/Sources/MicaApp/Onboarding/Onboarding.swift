import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct Onboarding: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var forward = true
    private var step: Int { browser.onboardingStep }
    @Namespace private var selection
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 720
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if !compact {
                        Text("mica").font(.system(size: 22, weight: .light)).tracking(-0.8).foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, Space.normal)
                    }
                    ForEach(0..<Self.steps, id: \.self) { index in
                        NavItem(title: stepName(index), symbol: stepSymbol(index), selected: index == step, namespace: selection, compact: compact) { go(to: index) }
                    }
                    Spacer()
                    if !compact {
                        Text(store.text("шаг ", "Шаг ") + "\(step + 1) / \(Self.steps)").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3)
                            .padding(.horizontal, 10).padding(.bottom, Space.micro)
                            .contentTransition(.numericText())
                    }
                }
                .padding(Space.normal)
                .frame(width: compact ? 60 : 228)
                .background(store.look.shell)
                Rectangle().fill(Palette.hairline).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.system(size: 22, weight: .regular)).tracking(-0.5).foregroundStyle(Palette.ink)
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.text2)
                    }
                    .id("title-\(step)")
                    .transition(stepTransition)
                    ZStack(alignment: .topLeading) {
                        stepContent.id(step).transition(stepTransition)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, Space.section)
                    HStack(spacing: Space.small) {
                        if step > 0 { Button(store.text("назад", "Назад")) { move(-1) }.buttonStyle(MButtonStyle(kind: .ghost)).transition(.opacity) }
                        Spacer()
                        Button(step == Self.steps - 1 ? store.text("начать", "Начать") : store.text("дальше", "Дальше")) {
                            if step < Self.steps - 1 { move(1) }
                            else { store.preferences.onboardingComplete = true; browser.showOnboarding = false; browser.focusAddress += 1 }
                        }
                        .buttonStyle(MButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, Space.normal)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.canvas)
            }
        }
        .environment(\.look, store.look)
        .animation(Motion.panel, value: step)
    }
    private func stepName(_ index: Int) -> String {
        switch index {
        case 0: return store.text("знакомство", "Знакомство")
        case 1: return store.text("перенос данных", "Перенос данных")
        case 2: return store.text("пространство", "Пространство")
        case 3: return store.text("оформление", "Оформление")
        case 4: return store.text("поиск и защита", "Поиск и защита")
        default: return store.text("сессия", "Сессия")
        }
    }
    private func stepSymbol(_ index: Int) -> String {
        switch index {
        case 0: return "hand.wave"
        case 1: return "square.and.arrow.down.on.square"
        case 2: return "sidebar.squares.left"
        case 3: return "paintbrush"
        case 4: return "shield.lefthalf.filled"
        default: return "square.stack"
        }
    }
    private func go(to index: Int) {
        guard index != step else { return }
        forward = index > step
        withMotion(Motion.panel ?? .easeInOut(duration: 0.12)) { browser.onboardingStep = index }
    }
    static let steps = 6
    private var stepTransition: AnyTransition {
        Motion.reduced ? .opacity : .asymmetric(insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity), removal: .opacity)
    }
    private func move(_ delta: Int) { forward = delta > 0; withMotion(Motion.panel ?? .easeInOut(duration: 0.12)) { browser.onboardingStep += delta } }
    private var title: String {
        switch step {
        case 0: return store.text("привет, это mica", "Привет, это mica")
        case 1: return store.text("всё уже на месте", "Всё уже на месте")
        case 2: return store.text("ваше пространство", "Ваше пространство")
        case 3: return store.text("цвет и иконка", "Цвет и иконка")
        case 4: return store.text("спокойнее с первого запуска", "Спокойнее с первого запуска")
        default: return store.text("работа остаётся с вами", "Работа остаётся с вами")
        }
    }
    private var subtitle: String {
        switch step {
        case 0: return store.text("язык, имя и стиль текста. всё можно поменять позже в настройках", "Язык, имя и стиль текста. Всё можно поменять позже в настройках")
        case 1: return store.text("история и закладки из другого браузера. шаг можно пропустить", "История и закладки из другого браузера. Шаг можно пропустить")
        case 2: return store.text("изменения видны сразу", "Изменения видны сразу")
        case 3: return store.text("тема окна, акцент и иконка mica в Доке", "Тема окна, акцент и иконка mica в Доке")
        case 4: return store.text("поиск, блокировка и разрешения", "Поиск, блокировка и разрешения")
        default: return store.text("вкладки, сессия и клавиши", "Вкладки, сессия и клавиши")
        }
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            ScrollView {
                VStack(alignment: .leading, spacing: Space.normal) {
                    GreetingPreview(store: store)
                    DefaultBrowserSetting(store: store)
                    SettingsGroup {
                        SettingRow(title: store.text("язык", "Язык")) { LanguagePicker(store: store, width: 300) }
                        SettingRow(title: store.text("текст интерфейса", "Текст интерфейса")) { CasePicker(store: store, width: 300) }
                        NameSettingRows(store: store)
                    }
                }
            }.scrollIndicators(.never)
        case 1:
            ScrollView { ImportView(store: store, manager: store.importer).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.never)
        case 2:
            VStack(alignment: .leading, spacing: Space.normal) {
                LayoutPreview(store: store).frame(height: 150)
                SettingsGroup {
                    SettingRow(title: store.text("вкладки", "Вкладки")) { LayoutPicker(store: store, width: 300) }
                    Toggle(store.text("свернуть боковую панель до иконок", "Свернуть боковую панель до иконок"), isOn: Binding(get: { store.preferences.sidebarCollapsed }, set: { value in withMotion(Motion.panel) { store.preferences.sidebarCollapsed = value } })).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false)).disabled(store.preferences.layout == .top)
                }
            }
        case 3:
            ScrollView {
                VStack(alignment: .leading, spacing: Space.normal) {
                    LayoutPreview(store: store).frame(height: 120)
                    ThemeGroup(store: store)
                    SettingsGroup {
                        Toggle(store.text("матовое стекло оболочки", "Матовое стекло оболочки"), isOn: $store.preferences.frosted).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
                    }
                    SettingsGroup(title: store.text("иконка приложения", "Иконка приложения")) { IconPicker(store: store).padding(14) }
                }
            }
            .scrollIndicators(.never)
        case 4:
            VStack(alignment: .leading, spacing: Space.normal) {
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 8) { Text(store.text("поисковик", "Поисковик")).font(.system(size: 13)).foregroundStyle(Palette.ink); SearchPicker(store: store) }.padding(.horizontal, 14).padding(.vertical, 10)
                    Hairline().padding(.leading, 14)
                    Toggle(isOn: $store.preferences.blocking) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.text("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"))
                            Text(store.text("локальные правила WebKit для известных сторонних доменов", "Локальные правила WebKit для известных сторонних доменов")).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                        }
                    }.toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
                }
                note("hand.raised", store.text("камера и микрофон запрашиваются только по запросу сайта, с его адресом в вопросе", "Камера и микрофон запрашиваются только по запросу сайта, с его адресом в вопросе"))
                note(Glyph.incognito, store.text("окна инкогнито не сохраняют историю, cookie и сессию", "Окна инкогнито не сохраняют историю, cookie и сессию"))
                note("arrow.down.circle", store.text("список блокировки обновляется только вручную в настройках", "Список блокировки обновляется только вручную в настройках"))
            }
        default:
            VStack(alignment: .leading, spacing: Space.normal) {
                SettingsGroup(footnote: store.text("после открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. после сбоя восстановятся адреса, но не несохранённые формы.", "После открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. После сбоя восстановятся адреса, но не несохранённые формы.")) {
                    Toggle(store.text("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), isOn: $store.preferences.restore).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                    Toggle(store.text("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), isOn: $store.preferences.lazyRestore).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false)).disabled(!store.preferences.restore)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Space.normal) {
                    shortcut("⌘L", store.text("адрес и поиск", "Адрес и поиск"))
                    shortcut("⌘T", store.text("новая вкладка", "Новая вкладка"))
                    shortcut("⌘⇧N", store.text("окно инкогнито", "Окно инкогнито"))
                    shortcut("⌃⌘S", store.text("боковая панель", "Боковая панель"))
                }
                .padding(.top, Space.small)
            }
        }
    }
    private func note(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Glyph(name: symbol, size: 12).foregroundStyle(Palette.text2).frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.track))
            Text(text).font(.system(size: 12.5)).foregroundStyle(Palette.text2)
        }
    }
    private func shortcut(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 10) { KeyHint(keys: keys).frame(minWidth: 44, alignment: .leading); Text(title).font(.system(size: 12.5)).foregroundStyle(Palette.text2) }
    }
}
