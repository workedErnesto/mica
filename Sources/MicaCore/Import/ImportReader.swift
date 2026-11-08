import Foundation

public enum ImportReader {
    /// Reads the chosen kinds from one profile.
    /// A kind that fails is skipped and reported in `failures`, so one locked file does not cancel the rest.
    public static func read(_ profile: ImportProfile, kinds: Set<ImportKind>) -> (bundle: ImportBundle, failures: [ImportKind: ImportError]) {
        var bundle = ImportBundle()
        var failures: [ImportKind: ImportError] = [:]
        func attempt(_ kind: ImportKind, _ work: () throws -> Void) {
            guard kinds.contains(kind) else { return }
            do { try work() } catch let error as ImportError { failures[kind] = error } catch { failures[kind] = .unreadable(error.localizedDescription) }
        }
        let path = profile.path
        switch profile.browser.family {
        case .chromium:
            attempt(.history) { bundle.history = try ChromiumReader.history(path) }
            attempt(.bookmarks) { bundle.bookmarks = try ChromiumReader.bookmarks(path) }
        case .gecko:
            attempt(.history) { bundle.history = try GeckoReader.history(path) }
            attempt(.bookmarks) { bundle.bookmarks = try GeckoReader.bookmarks(path) }
        case .safari:
            attempt(.history) { bundle.history = try SafariReader.history(path) }
            attempt(.bookmarks) { bundle.bookmarks = try SafariReader.bookmarks(path) }
        }
        return (bundle, failures)
    }
}
