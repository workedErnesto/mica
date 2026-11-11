import AppKit
import SwiftUI
import MicaCore

struct SidePanel: View {
    let panel: Panel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @State private var query = ""
    /// History of one profile only; nil shows every profile.
    @State private var profileFilter: UUID?
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
        if panel == .history && store.profiles.count > 1 && !browser.privateMode { ProfileFilter(selection: $profileFilter, store: store, browser: browser) }
        let filter = store.profiles.contains { $0.id == profileFilter } ? profileFilter : nil
        let visits = (panel == .history ? store.history : store.bookmarks).filter { visit in
            (query.isEmpty || visit.title.localizedCaseInsensitiveContains(query) || visit.url.absoluteString.localizedCaseInsensitiveContains(query))
                && (panel != .history || filter == nil || Profiles.owner(of: visit) == filter)
        }
        if visits.isEmpty {
            EmptyState(symbol: panel == .history ? "clock" : "bookmark", text: query.isEmpty ? (panel == .history ? browser.text("история пока пуста", "История пока пуста") : browser.text("добавьте закладку через ⌘D", "Добавьте закладку через ⌘D")) : browser.text("ничего не найдено", "Ничего не найдено"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: panel == .history ? [.sectionHeaders] : []) {
                    if panel == .history {
                        ForEach(History.days(visits), id: \.day) { group in
                            Section {
                                ForEach(group.visits) { visit in VisitRow(visit: visit, panel: panel, browser: browser, store: store).transition(.opacity) }
                            } header: { DayHeader(day: group.day, store: store, browser: browser) }
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

/// Day title above a group of history or download rows: today, yesterday, then weekday and date in the interface
/// language. No day means an old download whose date is unknown.
struct DayHeader: View {
    let day: Date?
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.top, Space.small).padding(.bottom, Space.micro)
            .background(Palette.surface)
            .accessibilityAddTraits(.isHeader)
    }
    private var title: String {
        guard let day else { return browser.text("раньше", "Раньше") }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return browser.text("сегодня", "Сегодня") }
        if calendar.isDateInYesterday(day) { return browser.text("вчера", "Вчера") }
        let format = DateFormatter()
        format.locale = browser.locale
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        format.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMy")
        let text = format.string(from: day)
        // Weekday and month names are authored words, so they follow the case style.
        return browser.prefs.lowercase ? text.lowercased(with: browser.locale) : text.prefix(1).uppercased(with: browser.locale) + text.dropFirst()
    }
}

/// Chips above the history list: every profile, or one of them.
private struct ProfileFilter: View {
    @Binding var selection: UUID?
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @Namespace private var chip
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.micro) {
                FilterChip(title: browser.text("все", "Все"), profile: nil, selected: selection == nil, namespace: chip) { withMotion(Motion.quick) { selection = nil } }
                ForEach(store.profiles) { profile in
                    FilterChip(title: browser.profileName(profile), profile: profile, selected: selection == profile.id, namespace: chip) { withMotion(Motion.quick) { selection = profile.id } }
                }
            }
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(browser.text("профиль", "Профиль"))
    }
}

private struct FilterChip: View {
    let title: String
    let profile: Profile?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let profile { ProfileMark(profile: profile, size: 14) }
                Text(title).font(.system(size: 11.5, weight: selected ? .medium : .regular)).lineLimit(1)
            }
            .foregroundStyle(selected || hover ? Palette.ink : Palette.text2)
            .padding(.leading, profile == nil ? 9 : 5).padding(.trailing, 9)
            .frame(height: 24)
            .background {
                if selected { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.pressed).matchedGeometryEffect(id: "chip", in: namespace) }
                else if hover { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.hover) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
