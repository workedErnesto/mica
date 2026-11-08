import AppKit
import SwiftUI
import AVFoundation
import MicaCore

/// What the start page will show above the search field: the greeting with the typed name, or the mica wordmark.
struct GreetingPreview: View {
    @ObservedObject var store: Store
    var body: some View {
        let greeting = Greeting.text(store.preferences, hour: Calendar.current.component(.hour, from: Date()), seed: 1)
        VStack(spacing: Space.small) {
            Spacer(minLength: 0)
            Text(greeting ?? "mica").font(.system(size: greeting == nil ? 30 : 24, weight: .light)).tracking(greeting == nil ? -1.1 : -0.7)
                .foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.tail)
                .contentTransition(.opacity)
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.surface)
                .overlay(alignment: .leading) {
                    HStack(spacing: Space.small) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                        Text(store.text("поиск или адрес", "Поиск или адрес")).font(.system(size: 12))
                    }
                    .foregroundStyle(Palette.text3).padding(.horizontal, Space.normal)
                }
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .frame(width: 300, height: 34)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.canvas).shadow(color: Palette.shadow, radius: 3, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(8)
        .frame(height: 150)
        .background(store.look.shell)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: 1))
        .animation(Motion.hover, value: greeting)
        .accessibilityElement().accessibilityLabel(store.text("начальная страница: ", "Начальная страница: ") + (greeting ?? "mica"))
    }
}
