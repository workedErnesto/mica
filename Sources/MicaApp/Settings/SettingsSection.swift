import AppKit
import SwiftUI
import AVFoundation
import MicaCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case space, appearance, start, search, session, permissions, about
    var id: String { rawValue }
    var symbol: String {
        switch self { case .space: return "sidebar.squares.left"; case .appearance: return "paintbrush"; case .start: return "square.grid.2x2"; case .search: return "shield.lefthalf.filled"; case .session: return "square.stack"; case .permissions: return "hand.raised"; case .about: return "info.circle" }
    }
    @MainActor func title(_ store: Store) -> String {
        switch self {
        case .space: return store.text("пространство", "Пространство")
        case .appearance: return store.text("оформление", "Оформление")
        case .start: return store.text("начальная страница", "Начальная страница")
        case .search: return store.text("поиск и защита", "Поиск и защита")
        case .session: return store.text("сессия и память", "Сессия и память")
        case .permissions: return store.text("разрешения сайтов", "Разрешения сайтов")
        case .about: return "mica"
        }
    }
}
