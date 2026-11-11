import AppKit
import SwiftUI
import AVFoundation
import MicaCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case space, appearance, start, profiles, search, session, transfer, permissions, passwords, about
    var id: String { rawValue }
    var symbol: String {
        switch self { case .space: return "sidebar.squares.left"; case .appearance: return "paintbrush"; case .start: return "square.grid.2x2"; case .profiles: return "person.crop.circle"; case .search: return "shield.lefthalf.filled"; case .session: return "square.stack"; case .transfer: return "square.and.arrow.down.on.square"; case .permissions: return "hand.raised"; case .passwords: return "key"; case .about: return "info.circle" }
    }
    @MainActor func title(_ browser: BrowserModel) -> String {
        switch self {
        case .space: return browser.text("пространство", "Пространство")
        case .appearance: return browser.text("оформление", "Оформление")
        case .start: return browser.text("начальная страница", "Начальная страница")
        case .profiles: return browser.text("профили", "Профили")
        case .search: return browser.text("поиск и защита", "Поиск и защита")
        case .session: return browser.text("сессия и память", "Сессия и память")
        case .transfer: return browser.text("перенос данных", "Перенос данных")
        case .permissions: return browser.text("разрешения сайтов", "Разрешения сайтов")
        case .passwords: return browser.text("пароли", "Пароли")
        case .about: return "mica"
        }
    }
}
