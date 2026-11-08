import AppKit
import Combine
import LocalAuthentication
import MicaCore

@MainActor
final class Passwords: ObservableObject {
    @Published private(set) var vault = Vault()
    @Published private(set) var error: String?
    @Published private(set) var loading = true
    private var storage: VaultStore?
    private var loadingTask: Task<Void, Never>?
    private let store: Store

    init(store: Store) {
        self.store = store
        let url = store.root.appendingPathComponent("passwords.vault")
        let account = ProcessInfo.processInfo.arguments.contains("--qa") ? "qa" : "default"
        guard FileManager.default.fileExists(atPath: url.path) else { loading = false; return }
        loadingTask = Task {
            do {
                let storage = try await Task.detached {
                    let key = try VaultKeychain.loadOrCreate(account: account, vaultExists: FileManager.default.fileExists(atPath: url.path))
                    return try VaultStore(url: url, keyData: key)
                }.value
                self.storage = storage
                vault = storage.vault
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    func waitUntilReady() async { await loadingTask?.value }

    func update(_ change: @escaping (inout Vault) -> Void) {
        guard let storage else {
            guard error == nil, !loading else { return }
            loading = true
            let url = store.root.appendingPathComponent("passwords.vault")
            let account = ProcessInfo.processInfo.arguments.contains("--qa") ? "qa" : "default"
            loadingTask = Task {
                do {
                    let storage = try await Task.detached {
                        let key = try VaultKeychain.loadOrCreate(account: account, vaultExists: FileManager.default.fileExists(atPath: url.path))
                        return try VaultStore(url: url, keyData: key)
                    }.value
                    self.storage = storage
                    try storage.update(change)
                    vault = storage.vault
                } catch { self.error = error.localizedDescription }
                loading = false
            }
            return
        }
        do { try storage.update(change); vault = storage.vault }
        catch { self.error = error.localizedDescription }
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: store.text("подтвердите доступ к паролю", "Подтвердите доступ к паролю"))
        } catch { return false }
    }
}
