import AppKit
import SwiftUI
import WebKit
import AVFoundation
import Combine
import MicaCore

@MainActor
final class Tab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab {
    let id: UUID
    weak var owner: BrowserModel?
    @Published var url: URL?
    @Published var title: String
    @Published var pinned: Bool
    @Published var phase: TabPhase
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canBack = false
    @Published var canForward = false
    @Published var secure = false
    @Published var error: String?
    @Published var capturing = false
    var webView: WKWebView?
    var navigationFailure: NSError?
    private var observations: [NSKeyValueObservation] = []
    private var passwordBridge: PasswordBridge?
    var saved: SavedTab { SavedTab(id: id, url: url, title: title, pinned: pinned) }
    init(saved: SavedTab, owner: BrowserModel, restored: Bool) {
        id = saved.id; url = saved.url; title = saved.title; pinned = saved.pinned
        phase = restored && saved.url != nil ? .restored : .fresh
        self.owner = owner; super.init()
    }
    func makeWebView(configuration: WKWebViewConfiguration? = nil) {
        guard webView == nil, let owner else { return }
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = owner.dataStore
        if !owner.privateMode { config.webExtensionController = owner.store.extensions.controller }
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = Tab.userAgentSuffix
        if configuration == nil && !owner.privateMode { passwordBridge = PasswordBridge(tab: self, controller: config.userContentController) }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = true
        view.isInspectable = ProcessInfo.processInfo.arguments.contains("--diagnostics")
        owner.store.blocker.apply(view)
        webView = view
        func observe<T>(_ key: KeyPath<WKWebView, T>, _ update: @escaping (Tab, WKWebView) -> Void) {
            observations.append(view.observe(key, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { if let self { update(self, web) } }
            })
        }
        observe(\.title) { tab, view in tab.title = view.title ?? tab.title }
        observe(\.url) { tab, view in if let url = view.url { tab.url = url }; tab.owner?.store.scheduleSession() }
        observe(\.isLoading) { tab, view in tab.loading = view.isLoading }
        observe(\.estimatedProgress) { tab, view in tab.progress = view.estimatedProgress }
        observe(\.canGoBack) { tab, view in tab.canBack = view.canGoBack }
        observe(\.canGoForward) { tab, view in tab.canForward = view.canGoForward }
        observe(\.hasOnlySecureContent) { tab, view in tab.secure = view.hasOnlySecureContent && view.url?.scheme == "https" && view.serverTrust != nil }
        observe(\.cameraCaptureState) { tab, view in tab.capturing = view.cameraCaptureState != .none || view.microphoneCaptureState != .none }
        observe(\.microphoneCaptureState) { tab, view in tab.capturing = view.cameraCaptureState != .none || view.microphoneCaptureState != .none }
    }
    /// WKWebView omits the `Version/... Safari/...` token by default and some sites then treat it as an unknown bot.
    /// mica uses the engine it runs on, so it reports the installed Safari version of the same system WebKit.
    static let userAgentSuffix: String = {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let version = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "18.0"
        return "Version/\(version) Safari/605.1.15"
    }()
    func ensureLoaded() {
        guard phase != .live && phase != .terminated, let url else { return }
        load(url)
    }
    func load(_ url: URL) {
        guard AddressParser.navigable(url) || owner?.store.extensions.controller.extensionContext(for: url) != nil else { return }
        makeWebView(); error = nil; navigationFailure = nil; secure = false; phase = .live
        self.url = url
        webView?.load(URLRequest(url: url))
        owner?.objectWillChange.send()
        owner?.store.scheduleSession()
    }
    func reload() {
        if phase == .terminated || webView == nil || webView?.backForwardList.currentItem == nil { if let url { load(url) } }
        else { error = nil; webView?.reload() }
    }
    func dispose() {
        observations.removeAll()
        if passwordBridge != nil { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "micaPasswords", contentWorld: .world(name: "mica.passwords")); passwordBridge = nil }
        webView?.stopLoading(); webView?.setCameraCaptureState(.none, completionHandler: nil); webView?.setMicrophoneCaptureState(.none, completionHandler: nil)
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView?.removeFromSuperview(); webView = nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        secure = false; error = nil; navigationFailure = nil
        if owner?.privateMode == false { owner?.store.extensions.controller.didChangeTabProperties([.loading, .URL], for: self) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        secure = webView.url?.scheme == "https" && webView.hasOnlySecureContent && webView.serverTrust != nil
        owner?.store.record(self); owner?.store.scheduleSession()
        if owner?.privateMode == false { owner?.store.extensions.controller.didChangeTabProperties([.title, .URL, .loading], for: self) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func failed(_ error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled && ns.code != 102 else { return }
        if let failedURL = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL, AddressParser.navigable(failedURL) { url = failedURL }
        self.error = error.localizedDescription; navigationFailure = ns; secure = false; loading = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        phase = .terminated; loading = false
        error = owner?.text("процесс страницы завершён системой. восстановите страницу; несохранённые формы могут быть потеряны.", "Процесс страницы завершён системой. Восстановите страницу; несохранённые формы могут быть потеряны.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        if AddressParser.navigable(url) || owner?.store.extensions.controller.extensionContext(for: url) != nil {
            if navigationAction.modifierFlags.contains(.command), navigationAction.navigationType == .linkActivated {
                owner?.open(url, background: !navigationAction.modifierFlags.contains(.shift)); decisionHandler(.cancel); return
            }
            if navigationAction.targetFrame?.isMainFrame == true { self.url = url }
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { Task { await owner?.external(url) } }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { owner?.downloads.add(download, tab: self) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { owner?.downloads.add(download, tab: self) }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodServerTrust else { completionHandler(.performDefaultHandling, nil); return }
        guard challenge.previousFailureCount < 2 else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let alert = NSAlert(); alert.messageText = owner?.text("вход на сайт", "Вход на сайт") ?? "mica"; alert.informativeText = challenge.protectionSpace.host
        let fields = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 60)); fields.orientation = .vertical; fields.spacing = 8
        let username = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); username.placeholderString = owner?.text("имя пользователя", "Имя пользователя")
        let password = NSSecureTextField(frame: username.frame); password.placeholderString = owner?.text("пароль", "Пароль")
        fields.addArrangedSubview(username); fields.addArrangedSubview(password); alert.accessoryView = fields
        alert.addButton(withTitle: owner?.text("войти", "Войти") ?? "OK"); alert.addButton(withTitle: owner?.text("отмена", "Отмена") ?? "Cancel")
        let finish: (NSApplication.ModalResponse) -> Void = { result in completionHandler(result == .alertFirstButtonReturn ? .useCredential : .cancelAuthenticationChallenge, result == .alertFirstButtonReturn ? URLCredential(user: username.stringValue, password: password.stringValue, persistence: .none) : nil) }
        if let window = owner?.controller?.window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let owner else { return nil }
        let tab = owner.add(activate: true, configuration: configuration)
        tab.phase = .live; tab.url = navigationAction.request.url
        return tab.webView
    }
    func webViewDidClose(_ webView: WKWebView) { owner?.close(self) }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        Task { _ = await ask(title: Origin.string(frame.request.url) ?? "mica", detail: message, buttons: ["OK"], window: owner?.controller?.window); completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        Task { let result = await ask(title: Origin.string(frame.request.url) ?? "mica", detail: message, buttons: [owner?.text("отмена", "Отмена") ?? "Cancel", "OK"], window: owner?.controller?.window); completionHandler(result == 1) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert(); alert.messageText = Origin.string(frame.request.url) ?? "mica"; alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); field.stringValue = defaultText ?? ""; alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: owner?.text("отмена", "Отмена") ?? "Cancel")
        if let window = owner?.controller?.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) } }
        else { completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        panel.message = Origin.string(frame.request.url) ?? "mica"
        if let window = owner?.controller?.window { panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) } }
        else { completionHandler(panel.runModal() == .OK ? panel.urls : nil) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        Task {
            if ProcessInfo.processInfo.arguments.contains("--diagnostics"), owner?.privateMode == false { FileHandle.standardError.write(Data("media-request origin=\(origin.protocol)://\(origin.host):\(origin.port), frame=\(frame.securityOrigin.protocol)://\(frame.securityOrigin.host):\(frame.securityOrigin.port)\n".utf8)) }
            guard let owner else { decisionHandler(.deny); return }
            @MainActor func keyFor(_ value: WKSecurityOrigin) -> String? {
                var parts = URLComponents(); parts.scheme = value.protocol; parts.host = value.host
                if value.port > 0 { parts.port = value.port }
                return Origin.string(parts.url)
            }
            guard let key = keyFor(origin), Origin.secure(key), keyFor(frame.securityOrigin) == key else { decisionHandler(.deny); return }
            let capabilities: [SiteCapability] = type == .camera ? [.camera] : type == .microphone ? [.microphone] : [.camera, .microphone]
            for capability in capabilities {
                let records = owner.privateMode ? owner.transientPermissions : owner.store.permissions
                let decision = records.first { $0.origin == key && $0.capability == capability }?.decision ?? .ask
                if decision == .deny { decisionHandler(.deny); return }
                if decision == .ask {
                    guard owner.selectedID == id else { decisionHandler(.deny); return }
                    let label = capability == .camera ? owner.text("камера", "Камера") : owner.text("микрофон", "Микрофон")
                    let answer = await ask(title: key + ": " + label, detail: owner.text("сайт запрашивает доступ для записи или звонка. macOS отдельно проверит системное разрешение.", "Сайт запрашивает доступ для записи или звонка. macOS отдельно проверит системное разрешение.") + (frame.isMainFrame ? "" : "\n" + owner.text("запрос из встроенного фрейма на ", "Запрос из встроенного фрейма на ") + (Origin.string(webView.url) ?? "")), buttons: [owner.text("запретить", "Запретить"), owner.text("разрешить один раз", "Разрешить один раз"), owner.text("разрешить для сайта", "Разрешить для сайта")], window: owner.controller?.window)
                    if answer != 1 {
                        let choice: Decision = answer == 2 ? .allow : .deny
                        if owner.privateMode { owner.transientPermissions.removeAll { $0.origin == key && $0.capability == capability }; owner.transientPermissions.append(SitePermission(origin: key, capability: capability, decision: choice)) }
                        else { owner.store.setPermission(origin: key, capability: capability, decision: choice) }
                    }
                    if answer == 0 { decisionHandler(.deny); return }
                }
                let media: AVMediaType = capability == .camera ? .video : .audio
                let status = AVCaptureDevice.authorizationStatus(for: media)
                var allowed = status == .authorized
                if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: media) }
                guard allowed else { owner.message = owner.text("доступ запрещён macOS. разрешения можно изменить в системных настройках конфиденциальности.", "Доступ запрещён macOS. Разрешения можно изменить в системных настройках конфиденциальности."); decisionHandler(.deny); return }
            }
            decisionHandler(.grant)
        }
    }
    // Public WebExtensions bridge. Private data is never attached to a controller.
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { owner?.tabs.firstIndex { $0.id == id } ?? 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { title }
    func url(for context: WKWebExtensionContext) -> URL? { url }
    func isPinned(for context: WKWebExtensionContext) -> Bool { pinned }
    func isSelected(for context: WKWebExtensionContext) -> Bool { owner?.selectedID == id }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !loading }
    func size(for context: WKWebExtensionContext) -> CGSize { webView?.bounds.size ?? .zero }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(webView?.pageZoom ?? 1) }
    func setZoomFactor(_ factor: Double, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { webView?.pageZoom = CGFloat(min(3, max(0.5, factor))); completionHandler(nil) }
    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { owner?.select(self); completionHandler(nil) }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { owner?.close(self); completionHandler(nil) }
    func setPinned(_ value: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { if pinned != value { owner?.pin(self) }; completionHandler(nil) }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard AddressParser.navigable(url) || owner?.store.extensions.controller.extensionContext(for: url) != nil else { completionHandler(MicaError.message("unsupported navigation scheme")); return }
        load(url); completionHandler(nil)
    }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if fromOrigin, let webView, webView.backForwardList.currentItem != nil { error = nil; webView.reloadFromOrigin() }
        else { reload() }
        completionHandler(nil)
    }
    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        guard let owner, !owner.privateMode else { completionHandler(nil, MicaError.message("private data unavailable")); return }
        let copy = owner.add(saved: SavedTab(url: configuration.url ?? url, title: title, pinned: configuration.shouldBePinned), activate: configuration.shouldBeActive)
        completionHandler(copy, nil)
    }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { owner?.privateMode == false }
    func shouldBypassPermissions(for context: WKWebExtensionContext) -> Bool { false }
}
