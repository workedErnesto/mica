import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct ErrorPage: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    let error: String
    var body: some View {
        ZStack {
            Palette.canvas
            VStack(alignment: .leading, spacing: Space.normal) {
                Image(systemName: tab.phase == .terminated ? "arrow.triangle.2.circlepath" : (-1206 ... -1200).contains(tab.navigationFailure?.code ?? 0) ? "lock.trianglebadge.exclamationmark" : "wifi.exclamationmark")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.text2)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.track))
                Text(tab.phase == .terminated ? browser.text("страница остановлена", "Страница остановлена") : browser.text("страница недоступна", "Страница недоступна"))
                    .font(.system(size: 24, weight: .regular)).tracking(-0.4).foregroundStyle(Palette.ink).padding(.top, Space.small)
                if let host = tab.url?.host { Text(host).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text2).textSelection(.enabled) }
                Text(error).font(.system(size: 13)).foregroundStyle(Palette.text2).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.small) {
                    Button(tab.phase == .terminated ? browser.text("восстановить", "Восстановить") : browser.text("повторить", "Повторить")) { tab.reload() }.buttonStyle(MButtonStyle(kind: .primary))
                    Button(browser.text("назад", "Назад")) { tab.error = nil; tab.webView?.goBack() }.buttonStyle(MButtonStyle(kind: .secondary)).disabled(!tab.canBack)
                }
                .padding(.top, Space.small)
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(40)
        }
    }
}
