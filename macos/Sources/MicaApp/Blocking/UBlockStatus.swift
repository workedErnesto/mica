import SwiftUI

/// What mica does with uBlock Origin's filters: the rule counts, building and updating, the last list update.
struct UBlockStatus: View {
    @ObservedObject var engine: UBlockEngine
    @ObservedObject var browser: BrowserModel
    let enabled: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if enabled {
                HStack(spacing: 6) {
                    if engine.compiling || engine.updating { ProgressView().controlSize(.mini).transition(.opacity) }
                    Text(engine.status).font(.system(size: 11)).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let date = engine.listsUpdated {
                    Text(browser.text("списки обновлены ", "Списки обновлены ") + date.formatted(.dateTime.day().month().hour().minute().locale(browser.locale))).font(.system(size: 11)).foregroundStyle(Palette.text3)
                }
                Text(browser.text("блокировка действует и в окнах инкогнито", "Блокировка действует и в окнах инкогнито")).font(.system(size: 11)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(browser.text("выключено, фильтры не применяются", "Выключено, фильтры не применяются")).font(.system(size: 11)).foregroundStyle(Palette.text3)
            }
        }
        .animation(Motion.quick, value: engine.compiling || engine.updating)
    }
}
