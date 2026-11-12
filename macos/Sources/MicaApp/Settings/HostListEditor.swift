import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct HostListEditor: View {
    @Binding var hosts: [String]
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var input = ""
    @State private var invalid = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.small) {
                MTextField(placeholder: "example.com", text: $input, symbol: "globe", selectionStyle: true) { add() }
                    .onChange(of: input) { _, value in store.settingsDraft = value }
                Button(browser.text("добавить", "Добавить")) { add() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(input.isEmpty)
            }
            .padding(10)
            if invalid { Text(browser.text("нужен домен без пути, например mail.example.com", "Нужен домен без пути, например mail.example.com")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, Space.small).transition(.opacity) }
            ForEach(hosts, id: \.self) { host in
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        Text(host).font(.system(size: 13)).foregroundStyle(Palette.ink)
                        Spacer()
                        IconButton(symbol: "minus.circle", label: browser.text("удалить ", "Удалить ") + host, size: 24) { withMotion(Motion.quick) { hosts.removeAll { $0 == host } } }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.hover, value: invalid)
    }
    private func add() {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (try? BlockingRules.parseDomains(host)) == [host] else { invalid = true; return }
        invalid = false
        if !hosts.contains(host) { withMotion(Motion.quick) { hosts.append(host) } }
        input = ""; store.settingsDraft = ""
    }
}
