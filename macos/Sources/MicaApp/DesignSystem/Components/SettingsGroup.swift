import AppKit
import SwiftUI
import AVFoundation
import MicaCore

/// Grouped settings surface: rows separated by inset hairlines.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.small) {
            if let title { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2) }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            if let footnote { Text(footnote).font(.system(size: 11.5)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true).lineSpacing(2) }
        }
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    var info: String?
    var detail: String?
    var divider = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Space.normal) {
                    labels.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    trailing
                }
                VStack(alignment: .leading, spacing: Space.small) {
                    labels
                    trailing
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            if divider { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14) }
        }
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                if let info { InfoTip(title: title, text: info) }
            }
            if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Question mark next to a setting title; the explanation opens on click so the row itself stays short.
struct InfoTip: View {
    let title: String
    let text: String
    @State private var shown = false
    @State private var hover = false
    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover || shown ? Palette.text2 : Palette.text3)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .accessibilityLabel(Store.shared.text("что это: ", "Что это: ") + title)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.small) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.text2).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(width: 300, alignment: .leading)
        }
    }
}

struct RowInset: ViewModifier {
    let divider: Bool
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content.font(.system(size: 13)).foregroundStyle(Palette.ink).padding(.horizontal, 14).padding(.vertical, 10)
            if divider { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14) }
        }
    }
}
