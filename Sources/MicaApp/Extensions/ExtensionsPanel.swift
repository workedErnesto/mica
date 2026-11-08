import AppKit
import SwiftUI
import MicaCore

struct ExtensionsPanel: View {
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            if browser.privateMode { Text(browser.text("расширения работают только в обычных окнах", "Расширения работают только в обычных окнах")).font(.system(size: 11.5)).foregroundStyle(Palette.text3) }
            MTextField(placeholder: browser.text("найти в Firefox Add-ons", "Найти в Firefox Add-ons"), text: $query, symbol: "magnifyingglass") { manager.search(query) }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.small) {
                    HStack {
                        Text(browser.text("установленные", "Установленные")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
                        Spacer()
                        Button(browser.text("с диска…", "С диска…")) { manager.chooseImport() }.buttonStyle(MButtonStyle(kind: .ghost, compact: true)).disabled(manager.busy)
                    }
                    if manager.records.isEmpty { Text(browser.text("пока ничего не установлено", "Пока ничего не установлено")).font(.system(size: 12)).foregroundStyle(Palette.text3).padding(.vertical, Space.micro) }
                    ForEach(manager.records) { record in InstalledExtension(record: record, manager: manager, browser: browser).transition(.opacity) }
                    Text(browser.text("каталог", "Каталог")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2).padding(.top, Space.normal)
                    Text(manager.catalogStatus.isEmpty ? browser.text("каталог Firefox Add-ons загружается только по вашему поиску", "Каталог Firefox Add-ons загружается только по вашему поиску") : manager.catalogStatus).font(.system(size: 11.5)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true)
                    ForEach(manager.catalog) { entry in CatalogCard(entry: entry, manager: manager, browser: browser).transition(.opacity) }
                    ChromeStoreSection(manager: manager, browser: browser).padding(.top, Space.normal)
                }
                .animation(Motion.quick, value: manager.catalog.map(\.id))
                .animation(Motion.quick, value: manager.records.map(\.id))
            }
            .scrollIndicators(.never)
        }
    }
}

struct InstalledExtension: View {
    let record: ExtensionRecord
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    @State private var anchor = PopupAnchor()
    @State private var hover = false
    private var sourceName: String { record.source.hasPrefix("amo:") ? ", Firefox Add-ons" : record.source.hasPrefix("cws:") ? ", Chrome Web Store" : "" }
    var body: some View {
        let context = manager.contexts[record.id]
        let enabled = context != nil
        let runnable = enabled && !browser.privateMode
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // The header runs the extension, like its button in the top bar.
                Button { manager.popupAnchor = anchor.view; manager.action(record, tab: browser.selected) } label: {
                    HStack(spacing: 10) {
                        SwiftUI.Group {
                            if let image = context?.webExtension.icon(for: CGSize(width: 28, height: 28)) { Image(nsImage: image).resizable().interpolation(.high).frame(width: 28, height: 28) }
                            else { Monogram(host: record.name, size: 28) }
                        }
                        .opacity(enabled ? 1 : 0.5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(record.version + sourceName).font(.system(size: 11)).foregroundStyle(Palette.text3).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover && runnable ? Palette.hover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .background(PopupAnchorView(anchor: anchor))
                .disabled(!runnable)
                .onHover { hover = $0 }
                .animation(Motion.hover, value: hover)
                .accessibilityLabel(browser.text("открыть ", "Открыть ") + record.name)
                MenuButton(label: browser.text("действия", "Действия"), size: 26) {
                    MenuEntry.item(browser.text("настройки расширения", "Настройки расширения"), enabled: manager.contexts[record.id]?.optionsPageURL != nil && !browser.privateMode) { manager.options(record) }
                    MenuEntry.item(browser.text("разрешить текущий сайт", "Разрешить текущий сайт"), enabled: !browser.privateMode && browser.selected?.url != nil) { Task { await manager.allowCurrentSite(record, tab: browser.selected) } }
                    MenuEntry.item(browser.text("отозвать доступ к сайтам", "Отозвать доступ к сайтам")) { Task { await manager.revokeHosts(record) } }
                    MenuEntry.item(browser.text("обновить с диска", "Обновить с диска")) { manager.chooseImport(replacing: record) }
                    MenuEntry.divider
                    MenuEntry.item(browser.text("удалить", "Удалить"), destructive: true) { Task { await manager.remove(record) } }
                }
                SwitchKnob(isOn: Binding(get: { enabled }, set: { _ in Task { await manager.toggle(record) } }))
                    .accessibilityLabel(record.name)
            }
            if let warning = manager.compatibility[record.id] { Text(warning).font(.system(size: 11)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true) }
            if let error = manager.errors[record.id] { Text(error).font(.system(size: 11)).foregroundStyle(Palette.danger).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            Text("API: " + record.permissions.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Palette.text3).textSelection(.enabled).lineLimit(3)
            Text(browser.text("сайты: ", "Сайты: ") + (record.hosts.isEmpty ? browser.text("доступ не выдан", "доступ не выдан") : record.hosts.joined(separator: ", "))).font(.system(size: 11)).foregroundStyle(Palette.text3).textSelection(.enabled).lineLimit(3)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).fill(Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

struct CatalogCard: View {
    let entry: CatalogEntry
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    var body: some View {
        let existing = manager.installed(entry)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Monogram(host: entry.name, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("Firefox Add-ons, " + entry.version).font(.system(size: 11)).foregroundStyle(Palette.text3)
                }
            }
            Text(entry.summary).font(.system(size: 11.5)).foregroundStyle(Palette.text2).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if !entry.permissions.isEmpty { Text(browser.text("заявленные права: ", "Заявленные права: ") + entry.permissions.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Palette.text3).textSelection(.enabled).lineLimit(3) }
            HStack(spacing: 6) {
                if manager.installing == entry.id {
                    Text(browser.text("загрузка и проверка…", "Загрузка и проверка…")).font(.system(size: 11.5)).foregroundStyle(Palette.text2).frame(height: 26)
                } else if let existing, existing.version == entry.version {
                    Label(browser.text("установлено", "Установлено"), systemImage: "checkmark").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text2).frame(height: 26)
                } else if entry.download != nil && entry.sha256 != nil {
                    Button(existing == nil ? browser.text("установить", "Установить") : browser.text("обновить до ", "Обновить до ") + entry.version) { Task { await manager.installFromCatalog(entry, replacing: existing) } }
                        .buttonStyle(MButtonStyle(kind: .primary, compact: true)).disabled(browser.privateMode || manager.busy || manager.installing != nil)
                }
                Button(browser.text("страница и лицензия", "Страница и лицензия")) { browser.open(entry.source) }.buttonStyle(MButtonStyle(kind: .ghost, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).fill(Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .animation(Motion.hover, value: manager.installing)
    }
}
