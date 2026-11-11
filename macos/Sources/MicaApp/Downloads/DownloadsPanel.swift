import AppKit
import SwiftUI
import MicaCore

/// Downloads in the library panel, laid out like history: search, rows grouped by day, actions on hover.
struct DownloadsPanel: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var browser: BrowserModel
    @State private var query = ""
    var body: some View {
        MTextField(placeholder: browser.text("поиск", "Поиск"), text: $query, symbol: "magnifyingglass")
        let items = manager.items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        if items.isEmpty {
            EmptyState(symbol: "arrow.down.circle", text: query.isEmpty ? browser.text("загрузки появятся здесь", "Загрузки появятся здесь") : browser.text("ничего не найдено", "Ничего не найдено"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(Self.days(items), id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in DownloadRow(item: item, manager: manager, browser: browser).transition(.opacity) }
                        } header: { DayHeader(day: group.day, store: browser.store, browser: browser) }
                    }
                }
                .animation(Motion.quick, value: items.map(\.id))
            }
            .scrollIndicators(.never)
        }
    }

    /// Newest day first, rows inside a day newest first; downloads without a date go last.
    static func days(_ items: [DownloadItem], calendar: Calendar = .current) -> [(day: Date?, items: [DownloadItem])] {
        var result: [(day: Date?, items: [DownloadItem])] = []
        let sorted = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for item in sorted {
            let day = item.date.map { calendar.startOfDay(for: $0) }
            if let last = result.last, last.day == day { result[result.count - 1].items.append(item) }
            else { result.append((day, [item])) }
        }
        return result
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    let manager: DownloadManager
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    var body: some View {
        Button { if item.state == .complete { item.open() } } label: {
            HStack(spacing: 10) {
                DownloadBadge(item: item)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name.isEmpty ? browser.text("выбор файла", "Выбор файла") : item.name)
                        .font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 11)).foregroundStyle(item.state == .failed ? Palette.danger : Palette.text3).lineLimit(1)
                        .monospacedDigit().contentTransition(.opacity)
                    if let folder {
                        // Where the file lies; the folder button on hover shows it in Finder.
                        HStack(spacing: 4) {
                            Image(systemName: "folder").font(.system(size: 9))
                            Text(folder).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(Palette.text3)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: hover ? 64 : 24)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .overlay(alignment: .trailing) {
            if hover {
                HStack(spacing: 2) {
                    switch item.state {
                    case .running, .choosing:
                        IconButton(symbol: "xmark", label: browser.text("отменить", "Отменить"), size: 24) { item.cancel() }
                    case .cancelled, .failed:
                        IconButton(symbol: "arrow.clockwise", label: retryTitle, size: 24) { item.retry() }
                    case .complete:
                        IconButton(symbol: "folder", label: browser.text("показать в Finder", "Показать в Finder"), size: 24) { item.reveal() }
                    }
                    MenuButton(label: browser.text("действия", "Действия")) { menu }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: item.state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue([detail, folder].compactMap { $0 }.joined(separator: ", "))
        .accessibilityActions {
            if item.active { Button(browser.text("отменить", "Отменить")) { item.cancel() } }
            if item.state == .complete { Button(browser.text("показать в Finder", "Показать в Finder")) { item.reveal() } }
            if item.state == .cancelled || item.state == .failed { Button(retryTitle) { item.retry() } }
        }
    }

    @MenuBuilder private var menu: [MenuEntry] {
        if item.state == .complete {
            MenuEntry.item(browser.text("открыть", "Открыть"), symbol: "arrow.up.right") { item.open() }
            MenuEntry.item(browser.text("показать в Finder", "Показать в Finder"), symbol: "folder") { item.reveal() }
        }
        if let source = item.source {
            MenuEntry.item(browser.text("копировать адрес загрузки", "Копировать адрес загрузки"), symbol: "link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source.absoluteString, forType: .string) }
        }
        if item.active {
            MenuEntry.divider
            MenuEntry.item(browser.text("отменить", "Отменить"), symbol: "xmark", destructive: true) { item.cancel() }
        } else {
            MenuEntry.divider
            MenuEntry.item(browser.text("убрать из списка", "Убрать из списка"), symbol: "minus.circle") { withMotion(Motion.quick) { manager.remove(item) } }
        }
    }

    private var retryTitle: String { item.resumeData == nil ? browser.text("повторить", "Повторить") : browser.text("возобновить", "Возобновить") }

    /// Kind of file in words with its extension: "картинка PNG", "документ PDF"; English puts the extension first.
    private var typeLabel: String {
        let ext = (item.name as NSString).pathExtension.uppercased()
        let word: String
        switch item.kind {
        case .image: word = browser.text("картинка", "Картинка")
        case .video: word = browser.text("видео", "Видео")
        case .archive: word = browser.text("архив", "Архив")
        case .document: word = browser.text("документ", "Документ")
        case .other: word = browser.text("файл", "Файл")
        }
        guard !ext.isEmpty else { return word }
        return browser.textStyle.language == .en ? ext + " " + word.lowercased() : word + " " + ext
    }

    /// Folder of a finished file: "загрузки" for the Downloads folder, otherwise the folder's own name.
    private var folder: String? {
        guard item.state == .complete, let directory = item.destination?.deletingLastPathComponent().resolvingSymlinksInPath() else { return nil }
        if let downloads = PageSaver.downloadsFolder, directory.standardizedFileURL.path == downloads.standardizedFileURL.path { return browser.text("загрузки", "Загрузки") }
        return FileManager.default.displayName(atPath: directory.path)
    }

    /// Second line: type, size and time when finished, progress while running, the reason otherwise.
    private var detail: String {
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        switch item.state {
        case .running:
            if item.saving { return browser.text("сохраняется", "Сохраняется") }
            return item.total > 0 ? size(item.bytes) + " " + browser.text("из", "из") + " " + size(item.total) : size(item.bytes)
        case .complete:
            let time = item.date.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(browser.locale)) }
            return [typeLabel, item.size > 0 ? size(item.size) : nil, time].compactMap { $0 }.joined(separator: ", ")
        case .cancelled: return browser.text("отменено", "Отменено")
        case .failed: return item.failure ?? browser.text("ошибка загрузки", "Ошибка загрузки")
        case .choosing: return browser.text("ожидает выбора места", "Ожидает выбора места")
        }
    }
}

/// Leading mark of a download row. While the file arrives: one arrow inside a progress ring. When it lands: the
/// ring closes and a checkmark draws itself, held for `MotionTokens.doneHold`. Then: the icon of the file kind.
struct DownloadBadge: View {
    @ObservedObject var item: DownloadItem
    var size: CGFloat = Chrome.rowIcon
    @Environment(\.look) private var look
    private enum Phase { case progress, done, kind }
    private var phase: Phase { item.justFinished ? .done : item.active ? .progress : .kind }
    var body: some View {
        ZStack {
            switch phase {
            case .progress: ring.transition(Motion.pop)
            case .done: DrawnCheck(color: look.primary).transition(Motion.pop)
            case .kind: kind.transition(Motion.pop)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.quick ?? Motion.hover, value: phase)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 2)
            if item.state == .running {
                if item.total > 0 {
                    Circle().trim(from: 0, to: max(0.04, item.fraction)).stroke(look.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: item.fraction)
                } else { UnknownProgress(color: look.primary) }
            }
            Image(systemName: "arrow.down").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Palette.text2)
        }
        .padding(1)
    }

    private var kind: some View {
        let failed = item.state == .failed
        return Image(systemName: failed ? "exclamationmark.triangle" : Self.symbol(item.kind))
            .font(.system(size: size * 0.5, weight: .regular))
            .foregroundStyle(failed ? Palette.danger : Palette.text2)
            .opacity(item.state == .cancelled ? 0.5 : 1)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Palette.track))
    }

    static func symbol(_ kind: DownloadKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .archive: return "archivebox"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }
}

/// Size unknown: a quarter arc turns while bytes arrive. Reduce Motion keeps it still; the byte count still moves.
private struct UnknownProgress: View {
    let color: Color
    @State private var turning = false
    var body: some View {
        Circle().trim(from: 0, to: 0.25).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(turning ? 270 : -90))
            .onAppear {
                guard !Motion.reduced else { return }
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

/// A closed ring with a checkmark stroked from the short arm to the long one. Reduce Motion shows it whole.
private struct DrawnCheck: View {
    let color: Color
    @State private var drawn: CGFloat = Motion.reduced ? 1 : 0
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 2)
            CheckShape().trim(from: 0, to: drawn).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .padding(1)
        .onAppear {
            guard drawn < 1 else { return }
            withAnimation(.easeOut(duration: MotionTokens.checkDraw).delay(0.06)) { drawn = 1 }
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
        return path
    }
}
