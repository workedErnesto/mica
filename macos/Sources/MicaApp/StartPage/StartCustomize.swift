import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Start page block geometry. Tiles sit centred in 88 pt columns, so a 60 pt icon is inset 14 pt; block titles and
/// their controls use the same inset, and the customizing outline adds only vertical padding, so the blocks do not
/// shift sideways when customizing starts.
enum StartLayout {
    static let column: CGFloat = 88
    static let inset: CGFloat = (column - 60) / 2
    /// The title row is as tall as its 12 pt text; the 24 pt controls in it overhang the row.
    static let title: CGFloat = 15
    /// Outline padding above the title and below the tile labels, and the gap between the title and the tiles.
    /// The letters keep about 3 pt of their own line above the caps and below the baseline, so the visible
    /// distances come to the same 14 pt as the inset on the sides.
    static let gap: CGFloat = 11
    /// Height of the title capsule, the visibility toggle while customizing.
    static let control: CGFloat = 24
    /// Distance from the outline to the title capsule: its left edge sits Space.small before the title.
    static let controlInset: CGFloat = inset - Space.small
    /// Outline radius, concentric with the title capsule in its corner: the capsule's radius plus its distance.
    static let outline: CGFloat = control / 2 + controlInset
    /// Width of the search field, and of the page column while a row of tiles fits in it.
    static let field: CGFloat = 600
    /// Width of a row of `count` tiles.
    static func row(_ count: Int) -> CGFloat { CGFloat(count) * column + CGFloat(max(0, count - 1)) * Space.micro }
    /// Page column: wide enough for a row of `count` tiles (the user's "sites per row"), never narrower than the field.
    static func width(_ count: Int) -> CGFloat { max(field, row(count)) }
    /// Tiles in a row: the user's choice, fewer when the page is too narrow for it.
    static func columns(_ chosen: Int, fitting width: CGFloat) -> Int {
        max(1, min(chosen, Int((width + Space.micro) / (column + Space.micro))))
    }
}

/// A start page block's column: as wide as its widest part wants (the header's title and controls, a row of tiles,
/// the greeting), never wider than offered, and every part laid out at that width. So a block and its customizing
/// outline follow its own content instead of the widest block on the page.
struct StartBlockStack: Layout {
    var spacing: CGFloat = StartLayout.gap
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(proposal, subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let size = ProposedViewSize(width: bounds.width, height: nil)
            let height = subview.sizeThatFits(size).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
    private func width(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return min(ideal, proposal.width ?? ideal)
    }
}

/// A block of the start page while customizing: a dashed outline, concentric with the title capsule in its corner.
struct StartEditFrame: ViewModifier {
    let editing: Bool
    func body(content: Content) -> some View {
        content
            .padding(.vertical, editing ? StartLayout.gap : 0)
            .background {
                if editing {
                    RoundedRectangle(cornerRadius: StartLayout.outline, style: .continuous)
                        .strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .transition(.opacity)
                }
            }
    }
}

/// Title row of a start page block. While customizing, the title with an eye after it shows or hides the block,
/// and optional order buttons stand on the right. The row itself never dims, only the block content.
struct StartBlockHeader<Order: View>: View {
    let title: String
    let editing: Bool
    @Binding var shown: Bool
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @ViewBuilder var order: Order
    var body: some View {
        HStack(spacing: Space.small) {
            StartBlockTitle(title: title, editing: editing, shown: $shown, browser: browser)
            Spacer(minLength: 0)
            if editing { order.transition(.opacity) }
        }
        .frame(height: StartLayout.title)
        .padding(.horizontal, StartLayout.inset)
    }
}

/// A block title that, while customizing, becomes the block's visibility toggle: the eye after it fades in, so the
/// title itself never moves, and the whole capsule is the target. The outline radius follows from this capsule.
struct StartBlockTitle: View {
    let title: String
    let editing: Bool
    @Binding var shown: Bool
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    var body: some View {
        let lit = editing && hover
        let label = (shown ? browser.text("скрыть", "Скрыть") : browser.text("показать", "Показать")) + ": " + title
        Button { withMotion(Motion.quick) { shown.toggle() } } label: {
            HStack(spacing: Space.micro) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(lit ? Palette.text2 : Palette.text3)
                if editing {
                    VisibilityEye(hidden: !shown)
                        .foregroundStyle(lit ? Palette.ink : shown ? Palette.text2 : Palette.text3)
                        .frame(width: 20, height: 20)
                        .transition(.opacity)
                }
            }
            .padding(.leading, Space.small).padding(.trailing, Space.micro)
            .frame(height: StartLayout.control)
            .background(Capsule().fill(lit ? Palette.hover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .padding(.leading, -Space.small)
        .allowsHitTesting(editing)
        .onHover { hover = $0 }
        .animation(Motion.hover, value: lit)
        .help(editing ? label : "")
        .accessibilityRepresentation {
            if editing { Toggle(browser.text("показывать", "Показывать") + ": " + title, isOn: $shown) } else { Text(title) }
        }
    }
}

/// An eye that a slash crosses out when its block is hidden: the slash grows from its top end on the panel spring and
/// cuts a gap through the outline, the lid narrows and the pupil fades. With Reduce Motion only the slash and pupil fade.
struct VisibilityEye: View {
    let hidden: Bool
    var size: CGFloat = 17
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let unit = size / 24
        let line = StrokeStyle(lineWidth: 1.7 * unit, lineCap: .round, lineJoin: .round)
        ZStack {
            EyeLid().stroke(style: line)
                .scaleEffect(x: 1, y: hidden && !reduced ? 0.82 : 1)
            Circle().stroke(style: line)
                .frame(width: 5.6 * unit, height: 5.6 * unit)
                .scaleEffect(hidden && !reduced ? 0.4 : 1)
                .opacity(hidden ? 0 : 1)
        }
        .mask {
            Rectangle()
                .overlay { slash(5 * unit).blendMode(.destinationOut) }
                .compositingGroup()
        }
        .overlay { slash(1.7 * unit) }
        .frame(width: size, height: size)
        .animation(reduced ? Motion.hover : Motion.panelSpring, value: hidden)
        .accessibilityHidden(true)
    }
    /// The slash grows from its top end; with Reduce Motion it only fades.
    private func slash(_ width: CGFloat) -> some View {
        let drawn: CGFloat = hidden ? 1 : 0
        return EyeSlash().stroke(style: StrokeStyle(lineWidth: width, lineCap: .round))
            .scaleEffect(reduced ? 1 : drawn, anchor: UnitPoint(x: 4.5 / 24, y: 3.5 / 24))
            .opacity(reduced ? drawn : 1)
    }
}

/// Outline of the eye on a 24 unit grid.
private struct EyeLid: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(2.5, 12))
        path.addCurve(to: p(12, 5.7), control1: p(4.7, 7.8), control2: p(7.9, 5.7))
        path.addCurve(to: p(21.5, 12), control1: p(16.1, 5.7), control2: p(19.3, 7.8))
        path.addCurve(to: p(12, 18.3), control1: p(19.3, 16.2), control2: p(16.1, 18.3))
        path.addCurve(to: p(2.5, 12), control1: p(7.9, 18.3), control2: p(4.7, 16.2))
        path.closeSubpath()
        return path
    }
}

/// The slash across the eye, from the top left to the bottom right, on the same grid.
private struct EyeSlash: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4.5 * s, y: rect.minY + 3.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 20.5 * s, y: rect.minY + 19.5 * s))
        return path
    }
}

extension StartBlockHeader where Order == EmptyView {
    init(title: String, editing: Bool, shown: Binding<Bool>, store: Store, browser: BrowserModel) {
        self.init(title: title, editing: editing, shown: shown, store: store, browser: browser) { EmptyView() }
    }
}

/// Quiet entry to customizing, in the corner of the start page.
struct StartCustomizeButton: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11.5, weight: .medium))
                Text(browser.text("настроить", "Настроить")).font(.system(size: 12))
            }
            .foregroundStyle(hover ? Palette.ink : Palette.text3)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .help(browser.text("настроить начальную страницу", "Настроить начальную страницу"))
    }
}

/// Options that apply to the whole start page, under the live page while customizing.
struct StartCustomizeBar: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        let start = browser.prefs.start
        let defaults = StartPage()
        let changed = start.sections != defaults.sections || start.wordmark != defaults.wordmark || start.frequentCount != defaults.frequentCount
        HStack(spacing: Space.small) {
            Text(browser.text("сайтов в ряду", "Сайтов в ряду"))
                .font(.system(size: 12)).foregroundStyle(Palette.text2).fixedSize()
            Segmented(selection: $browser.prefs.start.frequentCount, options: StartPage.frequentChoices.map { ($0, String($0)) }, compact: true, label: browser.text("сайтов в ряду", "Сайтов в ряду"))
            Spacer(minLength: Space.small)
            IconButton(symbol: "arrow.counterclockwise", label: browser.text("вернуть как было", "Вернуть как было"), size: 28) {
                withMotion(Motion.quick) {
                    browser.prefs.start.sections = defaults.sections
                    browser.prefs.start.wordmark = defaults.wordmark
                    browser.prefs.start.frequentCount = defaults.frequentCount
                }
            }.disabled(!changed)
            IconButton(symbol: "gearshape", label: browser.text("все настройки", "Все настройки"), size: 28) {
                browser.customizingStart = false; browser.settingsSection = .start; browser.showSettings = true
            }
            done
        }
        .padding(.horizontal, Space.normal).padding(.vertical, 8)
        .frame(maxWidth: 520)
        .modifier(RaisedSurface(radius: Radius.panel))
    }
    private var done: some View {
        Button(browser.text("готово", "Готово")) { withMotion(Motion.panel) { browser.customizingStart = false } }
            .buttonStyle(MButtonStyle(kind: .primary, compact: true)).keyboardShortcut(.defaultAction).fixedSize()
    }
}
