import AppKit
import SwiftUI
import MicaCore

struct SidePanel: View {
    let panel: Panel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @State private var query = ""
    var title: String {
        switch panel {
        case .bookmarks: return browser.text("закладки", "Закладки")
        case .history: return browser.text("история", "История")
        case .downloads: return browser.text("загрузки", "Загрузки")
        case .extensions: return browser.text("расширения", "Расширения")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            HStack {
                Text(title).font(.system(size: 17, weight: .regular)).tracking(-0.3).foregroundStyle(Palette.ink)
                Spacer()
                IconButton(symbol: "xmark", label: browser.text("закрыть панель", "Закрыть панель")) { browser.panel = nil }
            }
            SwiftUI.Group {
                if panel == .extensions { ExtensionsPanel(manager: store.extensions, browser: browser) }
                else if panel == .downloads { DownloadsPanel(manager: browser.downloads, browser: browser) }
                else { visits }
            }
            .id(panel)
            .transition(.opacity)
        }
        .padding(14)
        .animation(Motion.hover, value: panel)
    }

    @ViewBuilder private var visits: some View {
        MTextField(placeholder: browser.text("поиск", "Поиск"), text: $query, symbol: "magnifyingglass")
        if panel == .history && browser.privateMode { Text(browser.text("история окна инкогнито не записывается", "История окна инкогнито не записывается")).font(.system(size: 11.5)).foregroundStyle(Palette.text3) }
        let visits = (panel == .history ? store.history : store.bookmarks).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
        if visits.isEmpty {
            EmptyState(symbol: panel == .history ? "clock" : "bookmark", text: query.isEmpty ? (panel == .history ? browser.text("история пока пуста", "История пока пуста") : browser.text("добавьте закладку через ⌘D", "Добавьте закладку через ⌘D")) : browser.text("ничего не найдено", "Ничего не найдено"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: panel == .history ? [.sectionHeaders] : []) {
                    if panel == .history {
                        ForEach(History.days(visits), id: \.day) { group in
                            Section {
                                ForEach(group.visits) { visit in VisitRow(visit: visit, panel: panel, browser: browser, store: store).transition(.opacity) }
                            } header: { DayHeader(day: group.day, store: store) }
                        }
                    } else {
                        ForEach(visits) { visit in VisitRow(visit: visit, panel: panel, browser: browser, store: store).transition(.opacity) }
                    }
                }
                .animation(Motion.quick, value: visits.map(\.id))
            }
            .scrollIndicators(.never)
        }
        if panel == .history && !store.history.isEmpty && !browser.privateMode {
            Button(browser.text("очистить историю…", "Очистить историю…")) { browser.showClearData = true }
                .buttonStyle(MButtonStyle(kind: .destructive, compact: true))
                .help(browser.text("очистить историю", "Очистить историю") + " ⌘⇧⌫")
        }
    }
}

/// Day title above a group of history rows: today, yesterday, then weekday and date in the interface language.
struct DayHeader: View {
    let day: Date
    @ObservedObject var store: Store
    var body: some View {
        Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.top, Space.small).padding(.bottom, Space.micro)
            .background(Palette.surface)
            .accessibilityAddTraits(.isHeader)
    }
    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return store.text("сегодня", "Сегодня") }
        if calendar.isDateInYesterday(day) { return store.text("вчера", "Вчера") }
        let format = DateFormatter()
        format.locale = store.locale
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        format.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMy")
        let text = format.string(from: day)
        // Weekday and month names are authored words, so they follow the case style.
        return store.preferences.lowercase ? text.lowercased(with: store.locale) : text.prefix(1).uppercased(with: store.locale) + text.dropFirst()
    }
}
