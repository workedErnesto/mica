import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct SiteInfo: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    private var file: URL? { tab.url?.isFileURL == true ? tab.url : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            HStack(spacing: 10) {
                Monogram(host: tab.url?.host, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file?.lastPathComponent ?? tab.url?.host ?? "mica").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).textSelection(.enabled).lineLimit(1)
                    if file != nil {
                        Label(browser.text("локальный файл на этом Mac", "Локальный файл на этом Mac"), systemImage: "doc")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.text2)
                    } else {
                        Label(tab.secure ? browser.text("соединение HTTPS", "Соединение HTTPS") : browser.text("защищённое соединение не подтверждено", "Защищённое соединение не подтверждено"), systemImage: tab.secure ? "lock.fill" : "exclamationmark.shield")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.text2)
                    }
                }
            }
            if let file {
                Text(file.path).font(.system(size: 11.5)).foregroundStyle(Palette.text3).textSelection(.enabled).lineLimit(2).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
            }
            if let host = tab.url?.host {
                Toggle(browser.text("блокировка рекламы на сайте", "Блокировка рекламы на сайте"), isOn: Binding(get: { store.preferences.blocking && BlockingRules.matchingExceptions(host: host, exceptions: store.preferences.blockingExceptions).isEmpty }, set: { value in
                    if value { let inherited = BlockingRules.matchingExceptions(host: host, exceptions: store.preferences.blockingExceptions); store.preferences.blockingExceptions.removeAll { inherited.contains($0) }; store.preferences.blocking = true }
                    else if BlockingRules.matchingExceptions(host: host, exceptions: store.preferences.blockingExceptions).isEmpty { store.preferences.blockingExceptions.append(host) }
                })).toggleStyle(MToggleStyle()).font(.system(size: 12.5))
                Text(browser.text("правила применяются к новым запросам; перезагрузите страницу для полной проверки", "Правила применяются к новым запросам; перезагрузите страницу для полной проверки")).font(.system(size: 11)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true)
            }
            if let origin = Origin.string(tab.url) {
                Hairline()
                ForEach(SiteCapability.allCases.filter { !(browser.privateMode && $0 == .notifications) }, id: \.self) { capability in
                    let records = browser.privateMode ? browser.transientPermissions : store.permissions
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.capabilityName(capability)).font(.system(size: 12)).foregroundStyle(Palette.text2)
                        Segmented(selection: Binding(get: { records.first { $0.origin == origin && $0.capability == capability }?.decision ?? .ask }, set: { decision in
                            if browser.privateMode { browser.transientPermissions.removeAll { $0.origin == origin && $0.capability == capability }; browser.transientPermissions.append(.init(origin: origin, capability: capability, decision: decision)); if decision != .allow { tab.webView?.setCameraCaptureState(.none, completionHandler: nil); tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil) } }
                            else { store.setPermission(origin: origin, capability: capability, decision: decision) }
                        }), options: [(.ask, browser.text("спрашивать", "Спрашивать")), (.allow, browser.text("разрешить", "Разрешить")), (.deny, browser.text("запретить", "Запретить"))], compact: true, fillsWidth: true, label: store.capabilityName(capability))
                    }
                }
            }
            if tab.capturing {
                HStack {
                    Label(browser.text("идёт запись с камеры или микрофона", "Идёт запись с камеры или микрофона"), systemImage: "mic.fill").font(.system(size: 12)).foregroundStyle(Palette.live)
                    Spacer()
                    Button(browser.text("остановить", "Остановить")) { tab.webView?.setCameraCaptureState(.none, completionHandler: nil); tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil) }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                }
            }
            if file == nil {
                Text(browser.text("геолокация: управляемый доступ недоступен в публичном WebKit этой версии macOS", "Геолокация: управляемый доступ недоступен в публичном WebKit этой версии macOS")).font(.system(size: 11)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}
