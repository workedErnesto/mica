import AppKit
import SwiftUI
import MicaCore

struct DownloadsPanel: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var browser: BrowserModel
    var body: some View {
        if manager.items.isEmpty { EmptyState(symbol: "arrow.down.circle", text: browser.text("загрузки появятся здесь", "Загрузки появятся здесь")) }
        else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.small) { ForEach(manager.items) { item in DownloadRow(item: item, browser: browser).transition(Motion.pop) } }
                    .animation(Motion.quick, value: manager.items.map(\.id))
            }
            .scrollIndicators(.never)
        }
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @ObservedObject var browser: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.small) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(item.state == .failed ? Palette.danger : Palette.text2)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.track))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? browser.text("выбор файла", "Выбор файла") : item.name).lineLimit(2).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(status).font(.system(size: 11.5)).foregroundStyle(Palette.text3).textSelection(.enabled).lineLimit(3)
                }
            }
            if item.state == .running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track)
                        Capsule().fill(Palette.primary).frame(width: item.total > 0 ? geo.size.width * item.fraction : geo.size.width * 0.12)
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.25), value: item.fraction)
            }
            HStack(spacing: 6) {
                switch item.state {
                case .running: Button(browser.text("отменить", "Отменить")) { item.cancel() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                case .complete:
                    Button(browser.text("открыть", "Открыть")) { item.open() }.buttonStyle(MButtonStyle(kind: .primary, compact: true))
                    Button(browser.text("показать в Finder", "Показать в Finder")) { item.reveal() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                case .cancelled, .failed: Button(item.resumeData == nil ? browser.text("повторить", "Повторить") : browser.text("возобновить", "Возобновить")) { item.retry() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                default: EmptyView()
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).fill(Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .animation(Motion.quick, value: item.state)
    }
    private var symbol: String {
        switch item.state { case .complete: return "checkmark"; case .failed: return "exclamationmark.triangle"; case .cancelled: return "xmark"; default: return "arrow.down" }
    }
    private var status: String {
        switch item.state {
        case .running: return item.total > 0 ? ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file) : ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        case .complete: return browser.text("сохранено", "Сохранено")
        case .cancelled: return browser.text("отменено", "Отменено")
        case .failed: return item.failure ?? browser.text("ошибка загрузки", "Ошибка загрузки")
        default: return browser.text("ожидает выбора места", "Ожидает выбора места")
        }
    }
}
