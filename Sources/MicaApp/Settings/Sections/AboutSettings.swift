import AppKit
import SwiftUI
import AVFoundation
import MicaCore

/// What mica is in two short paragraphs, then the version and the onboarding again. The signature sits in the pane's bottom inset.
struct AboutSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.normal) {
                Text(store.text("mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили.", "mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили."))
                Text(store.text("реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store и Firefox Add-ons. собственной телеметрии нет.", "Реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store и Firefox Add-ons. Собственной телеметрии нет."))
            }
            .font(.system(size: 13.5)).foregroundStyle(Palette.text2).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
            SettingsGroup {
                SettingRow(title: store.text("версия", "Версия"), divider: false) {
                    Text("0.2.0").font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.text2)
                }
            }
            Button(store.text("пройти знакомство ещё раз", "Пройти знакомство ещё раз")) {
                dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { browser.onboardingStep = 0; browser.showOnboarding = true }
            }
            .buttonStyle(MButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
