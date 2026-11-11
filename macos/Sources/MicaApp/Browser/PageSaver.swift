import AppKit
import WebKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import MicaCore

extension PageFormat {
    @MainActor func title(_ browser: BrowserModel) -> String {
        switch self {
        case .pdf: return "PDF"
        case .png: return browser.text("картинка PNG", "Картинка PNG")
        case .jpeg: return browser.text("картинка JPEG", "Картинка JPEG")
        case .html: return "HTML"
        }
    }
    var symbol: String {
        switch self { case .pdf: return "doc.text"; case .png: return "photo"; case .jpeg: return "camera"; case .html: return "chevron.left.forwardslash.chevron.right" }
    }
    var contentType: UTType {
        switch self { case .pdf: return .pdf; case .png: return .png; case .jpeg: return .jpeg; case .html: return .html }
    }
}

/// Saves the page of a tab as PDF (print pages), a PNG or JPEG picture of the whole page, or one HTML file with its
/// images. The format is picked in mica's own menu, the place in the system save panel opened on Downloads; the file
/// then appears in downloads with its type, size and folder. A tab showing a
/// file rather than a web page (a PDF, an image) saves that file through the ordinary download.
@MainActor
enum PageSaver {
    static func canSave(_ tab: Tab?) -> Bool {
        guard let tab, let url = tab.url, tab.webView != nil, tab.phase != .terminated else { return false }
        return ["http", "https", "file"].contains(url.scheme ?? "")
    }

    /// The format menu shared by the toolbar button and ⌘S.
    static func entries(_ tab: Tab, browser: BrowserModel) -> [MenuEntry] {
        PageFormat.allCases.map { format in MenuEntry.item(format.title(browser), symbol: format.symbol) { save(tab, browser: browser, format: format) } }
    }

    /// The user's Downloads folder: inside the sandbox a link to it, resolved to the real place.
    static var downloadsFolder: URL? { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath() }

    static func save(_ tab: Tab, browser: BrowserModel, format: PageFormat) {
        guard canSave(tab), let web = tab.webView, let page = tab.url else { return }
        Task {
            // A PDF or picture opened in the tab is already the file to keep.
            let type = try? await web.callAsyncJavaScript("return document.contentType", contentWorld: .defaultClient) as? String
            if let type, !["text/html", "application/xhtml+xml"].contains(type.lowercased()) {
                web.startDownload(using: URLRequest(url: page)) { download in browser.downloads.add(download, tab: tab) }
                return
            }
            guard let destination = await choose(tab: tab, page: page, browser: browser, format: format) else { return }
            let item = DownloadItem(saving: destination.lastPathComponent, destination: destination, tab: tab, manager: browser.downloads)
            browser.downloads.add(saved: item)
            run(item, tab: tab, format: format)
        }
    }

    /// The system save panel, expanded like a Finder window (folder sidebar, files of the folder with their kind),
    /// opened on Downloads with the page title as a free name there. The format was chosen in mica's menu, so the
    /// panel only allows that type. macOS keeps the expanded state in the app's own defaults under these keys.
    private static func choose(tab: Tab, page: URL, browser: BrowserModel, format: PageFormat) async -> URL? {
        UserDefaults.standard.set(true, forKey: "NSNavPanelExpandedStateForSaveMode")
        UserDefaults.standard.set(true, forKey: "NSNavPanelExpandedStateForSaveMode2")
        let panel = NSSavePanel()
        let proposed = PageExport.fileName(title: tab.title, url: page.absoluteString, format: format)
        if let folder = downloadsFolder {
            panel.directoryURL = folder
            panel.nameFieldStringValue = PageExport.availableName(proposed) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        } else { panel.nameFieldStringValue = proposed }
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let response: NSApplication.ModalResponse
        if let window = browser.controller?.window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        guard response == .OK else { return nil }
        return panel.url
    }

    private static func run(_ item: DownloadItem, tab: Tab, format: PageFormat) {
        item.saveAgain = { [weak item, weak tab] in
            guard let item, let tab else { return }
            item.failure = nil; item.fraction = 0.05; item.state = .running
            run(item, tab: tab, format: format)
        }
        item.work = Task { [weak item] in
            guard let item, let destination = item.destination else { return }
            let existed = FileManager.default.fileExists(atPath: destination.path)
            do {
                guard let web = tab.webView else { throw SaveFailure() }
                try await write(web, format: format, to: destination) { fraction in item.fraction = fraction }
                try Task.checkCancellation()
                item.savingFinished()
                tab.owner?.panel = .downloads
            } catch is CancellationError {
            } catch {
                // A new file left half written (a full disk) goes; a file the user agreed to replace is never removed.
                if !existed { try? FileManager.default.removeItem(at: destination) }
                if item.state == .cancelled { return }
                item.savingFailed(error is SaveFailure ? MicaError.message(Store.shared.text("не удалось сохранить страницу", "Не удалось сохранить страницу")) : error)
                tab.owner?.panel = .downloads
            }
        }
    }

    // MARK: Writing

    private static func write(_ web: WKWebView, format: PageFormat, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        _ = try? await web.callAsyncJavaScript(PageExport.prepareScript, contentWorld: .defaultClient)
        progress(0.25)
        switch format {
        case .pdf:
            // The print engine writes into a file of mica's own; the chosen file is written only once it is complete.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try await printPDF(web, to: temporary)
            let data = try Data(contentsOf: temporary)
            try Task.checkCancellation()
            try data.write(to: destination)
        case .png, .jpeg:
            let pdf = try await web.pdf(configuration: WKPDFConfiguration())
            progress(0.5)
            let scale = web.window?.backingScaleFactor ?? 2
            let data = try await Task.detached(priority: .userInitiated) { try picture(pdf: pdf, scale: scale, format: format) }.value
            try Task.checkCancellation()
            try data.write(to: destination)
        case .html:
            guard let page = try await web.callAsyncJavaScript(PageExport.serializeScript, contentWorld: .defaultClient) as? [String: Any],
                  let html = page["html"] as? String, let base = page["base"] as? String else { throw SaveFailure() }
            progress(0.45)
            let archive: Data = try await withCheckedThrowingContinuation { continuation in web.createWebArchiveData { continuation.resume(with: $0) } }
            progress(0.65)
            let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                let resources = try resourcesOf(archive: archive)
                return Data(SingleFilePage.build(html: html, base: base, resources: resources).utf8)
            }.value
            try Task.checkCancellation()
            try data.write(to: destination)
        }
        progress(1)
    }

    /// Something on the way gave nothing back; the row shows a plain sentence instead of an internal reason.
    struct SaveFailure: Error {}

    /// Print pages through the system print engine straight into the file: the page's print styles apply, the paper
    /// is the default one of the Mac. WebKit prints only through `runModal`; a plain `run()` keeps paginating.
    private static func printPDF(_ web: WKWebView, to destination: URL) async throws {
        guard let window = web.window else { throw SaveFailure() }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        let operation = web.printOperation(with: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        operation.view?.frame = web.bounds
        let printed = await PrintCompletion.run(operation, window: window)
        guard printed, FileManager.default.fileExists(atPath: destination.path) else { throw SaveFailure() }
    }

    nonisolated private static func picture(pdf: Data, scale: Double, format: PageFormat) throws -> Data {
        guard let page = PDFDocument(data: pdf)?.page(at: 0) else { throw SaveFailure() }
        let box = page.bounds(for: .mediaBox)
        guard let size = PageExport.imagePixels(width: box.width, height: box.height, scale: scale),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw SaveFailure() }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.scaleBy(x: Double(size.width) / box.width, y: Double(size.height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw SaveFailure() }
        let data = NSMutableData()
        let type = (format == .png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let target = CGImageDestinationCreateWithData(data, type, 1, nil) else { throw SaveFailure() }
        CGImageDestinationAddImage(target, image, format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        guard CGImageDestinationFinalize(target) else { throw SaveFailure() }
        return data as Data
    }

    /// Files of the main frame from a WebKit web archive (a property list). Frames keep their own addresses.
    nonisolated private static func resourcesOf(archive: Data) throws -> [PageResource] {
        guard let plist = try PropertyListSerialization.propertyList(from: archive, format: nil) as? [String: Any] else { return [] }
        return (plist["WebSubresources"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let url = entry["WebResourceURL"] as? String, let data = entry["WebResourceData"] as? Data else { return nil }
            return PageResource(url: url, mime: entry["WebResourceMIMEType"] as? String ?? "", data: data)
        }
    }
}

/// Bridges the print operation's delegate callback to async code.
@MainActor
final class PrintCompletion: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?
    private static var running: Set<PrintCompletion> = []
    static func run(_ operation: NSPrintOperation, window: NSWindow) async -> Bool {
        let completion = PrintCompletion()
        running.insert(completion)
        defer { running.remove(completion) }
        return await withCheckedContinuation { continuation in
            completion.continuation = continuation
            operation.runModal(for: window, delegate: completion, didRun: #selector(printed(_:success:context:)), contextInfo: nil)
        }
    }
    @objc func printed(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: success); continuation = nil
    }
}
