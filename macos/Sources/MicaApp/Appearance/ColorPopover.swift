import AppKit
import SwiftUI
import MicaCore

// mica's colour picker replaces the system colour panel: presets, a saturation and brightness field, a hue strip and
// the system eyedropper, in a small panel that grows from the control like the shell menus. Changes apply live.

@MainActor
final class PopoverModel: ObservableObject {
    @Published var shown = false
    var anchor: UnitPoint = .topLeading
}

/// One mica popover at a time, above the window so it can reach past its edge. Closes on a click elsewhere, Esc,
/// or when the window moves, resizes or mica loses focus.
@MainActor
final class MicaPopover {
    static let shared = MicaPopover()
    let model = PopoverModel()
    private var panel: MenuPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    func show<Content: View>(below rect: NSRect, in window: NSWindow?, @ViewBuilder content: () -> Content) {
        close(animated: false)
        model.shown = false
        let store = Store.shared
        let root = PopoverChrome(model: model) { content() }
            .environment(\.look, store.look(for: window))
            .environment(\.locale, store.locale)
        let host = FirstMouseHost(rootView: AnyView(root))
        let size = host.fittingSize
        let margin = MicaMenu.margin
        let content = NSSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        let screen = (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: rect.minX, y: rect.minY - 6 - content.height)
        var anchor = UnitPoint.topLeading
        if origin.y < screen.minY + 4 { origin.y = rect.maxY + 6; anchor = .bottomLeading }
        if origin.x + content.width > screen.maxX - 4 { origin.x = rect.maxX - content.width; anchor = anchor == .topLeading ? .topTrailing : .bottomTrailing }
        model.anchor = anchor
        let panel = MenuPanel(contentRect: NSRect(x: origin.x - margin, y: origin.y - margin, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        panel.contentView = host
        panel.orderFront(nil)
        self.panel = panel
        watch(window)
        withMotion(Motion.reduced ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.88)) { model.shown = true }
        NSAccessibility.post(element: host, notification: .created)
    }

    func close(animated: Bool = true) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let panel else { return }
        self.panel = nil
        if animated {
            withAnimation(.easeOut(duration: 0.1)) { model.shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { panel.orderOut(nil) }
        } else { panel.orderOut(nil) }
    }

    /// The eyedropper hides the panel while the user samples the screen; the click that picks must not close it.
    var sampling = false

    private func watch(_ window: NSWindow?) {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, event.window !== panel, !self.sampling else { return event }
            self.close()
            return event.type == .rightMouseDown ? event : nil
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if self?.sampling == false { self?.close() } }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close(); return nil
        } as Any)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in if self?.sampling == false { self?.close(animated: false) } } })
        if let window {
            for name in [NSWindow.willMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in Task { @MainActor in self?.close(animated: false) } })
            }
        }
    }
}

private struct PopoverChrome<Content: View>: View {
    @ObservedObject var model: PopoverModel
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: Palette.menuShadow, radius: 8, y: 3)
            .scaleEffect(model.shown || reduced ? 1 : 0.95, anchor: model.anchor)
            .opacity(model.shown ? 1 : 0)
            .padding(MicaMenu.margin)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

/// Colour in hue, saturation and brightness, the coordinates of the picker field. Hex in and out.
struct HSB: Equatable {
    var hue: Double, saturation: Double, brightness: Double
    init(hue: Double, saturation: Double, brightness: Double) { self.hue = hue; self.saturation = saturation; self.brightness = brightness }
    init(hex: String) {
        let c = HexColor.parse(hex) ?? (0.5, 0.5, 0.5)
        let color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        self.init(hue: color.hueComponent, saturation: color.saturationComponent, brightness: color.brightnessComponent)
    }
    var hex: String {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).usingColorSpace(.sRGB) ?? .gray
        return HexColor.string(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }
    var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }
}

struct ColorPanel: View {
    let presets: [String]
    let label: String
    let onChange: (String) -> Void
    @State private var value: HSB
    @State private var hex: String
    @ObservedObject private var store = Store.shared
    init(hex: String, presets: [String], label: String, onChange: @escaping (String) -> Void) {
        self.presets = presets; self.label = label; self.onChange = onChange
        let start = HexColor.parse(hex) == nil ? "#8D7B6A" : hex.uppercased()
        _value = State(initialValue: HSB(hex: start)); _hex = State(initialValue: start)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: min(8, max(1, presets.count))), alignment: .leading, spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    ColorDot(hex: preset, selected: preset == hex, size: 22) { pick(HSB(hex: preset), exact: preset) }
                }
            }
            SaturationField(value: $value) { commit() }
                .frame(width: 216, height: 132)
            HueStrip(value: $value) { commit() }
                .frame(width: 216, height: 14)
            HStack(spacing: Space.small) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: hex)).frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                Text(hex).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.text2).textSelection(.enabled)
                Spacer(minLength: 0)
                IconButton(symbol: "eyedropper", label: store.text("взять цвет с экрана", "Взять цвет с экрана"), size: 26) { sample() }
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
    private func pick(_ new: HSB, exact: String? = nil) {
        withMotion(Motion.quick) { value = new }
        hex = exact ?? new.hex
        onChange(hex)
    }
    private func commit() {
        let next = value.hex
        guard next != hex else { return }
        hex = next; onChange(next)
    }
    /// The system colour sampler: a magnifier over the whole screen, Esc cancels.
    private func sample() {
        MicaPopover.shared.sampling = true
        NSColorSampler().show { color in
            DispatchQueue.main.async {
                MicaPopover.shared.sampling = false
                guard let c = color?.usingColorSpace(.sRGB) else { return }
                let picked = HexColor.string(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
                pick(HSB(hex: picked), exact: picked)
            }
        }
    }
}

/// Saturation left to right, brightness bottom to top, for the current hue. Drag anywhere; arrows adjust with VoiceOver.
private struct SaturationField: View {
    @Binding var value: HSB
    let changed: () -> Void
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: Radius.icon, style: .continuous)
            ZStack {
                shape.fill(Color(hue: value.hue, saturation: 1, brightness: 1))
                shape.fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                shape.fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Palette.hairline, lineWidth: 1)
                Circle().fill(value.color).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .scaleEffect(dragging && !reduced ? 1.25 : 1)
                    .position(x: value.saturation * geo.size.width, y: (1 - value.brightness) * geo.size.height)
                    .animation(Motion.hover, value: dragging)
            }
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                dragging = true
                value.saturation = min(1, max(0, Double(drag.location.x / geo.size.width)))
                value.brightness = min(1, max(0, 1 - Double(drag.location.y / geo.size.height)))
                changed()
            }.onEnded { _ in dragging = false })
        }
        .accessibilityElement()
        .accessibilityLabel(Store.shared.text("яркость", "Яркость"))
        .accessibilityValue(String(Int((value.brightness * 100).rounded())) + "%")
        .accessibilityAdjustableAction { direction in
            value.brightness = min(1, max(0, value.brightness + (direction == .increment ? 0.05 : -0.05))); changed()
        }
    }
}

private struct HueStrip: View {
    @Binding var value: HSB
    let changed: () -> Void
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        GeometryReader { geo in
            let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: hues, startPoint: .leading, endPoint: .trailing))
                Capsule().strokeBorder(Palette.hairline, lineWidth: 1)
                Circle().fill(Color(hue: value.hue, saturation: 1, brightness: 1)).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .scaleEffect(dragging && !reduced ? 1.2 : 1)
                    .offset(x: value.hue * (geo.size.width - 16))
                    .animation(Motion.hover, value: dragging)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                dragging = true
                value.hue = min(0.999, max(0, Double((drag.location.x - 8) / (geo.size.width - 16))))
                if value.saturation < 0.05 { value.saturation = 0.6 }
                if value.brightness < 0.05 { value.brightness = 0.7 }
                changed()
            }.onEnded { _ in dragging = false })
        }
        .accessibilityElement()
        .accessibilityLabel(Store.shared.text("оттенок", "Оттенок"))
        .accessibilityValue(String(Int((value.hue * 360).rounded())) + "°")
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 1.0 / 36 : -1.0 / 36; value.hue = (value.hue + step + 1).truncatingRemainder(dividingBy: 1); changed()
        }
    }
}

/// Round colour choice: presets of the accent and profile backgrounds and the picker.
struct ColorDot: View {
    let hex: String
    let selected: Bool
    var size: CGFloat = 20
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button(action: action) {
            Circle().fill(Color(hex: hex))
                .frame(width: size - 6, height: size - 6)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Palette.ink : hover ? Palette.hairlineStrong : .clear, lineWidth: 1.5))
                .scaleEffect(hover && !reduced ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .help(hex).accessibilityLabel(hex).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Opens the colour panel under itself. Shows the current colour inside a hue ring when it is not one of the presets.
struct ColorWell: View {
    let hex: String
    let presets: [String]
    let label: String
    var size: CGFloat = 26
    let onChange: (String) -> Void
    @State private var anchor = PopupAnchor()
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let custom = !presets.contains(hex.uppercased())
        Button {
            guard let view = anchor.view, let window = view.window else { return }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            MicaPopover.shared.show(below: rect, in: window) { ColorPanel(hex: hex, presets: presets, label: label, onChange: onChange) }
        } label: {
            ZStack {
                Circle().strokeBorder(AngularGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 0.85, brightness: 0.95) }, center: .center), lineWidth: 2.5)
                if custom { Circle().fill(Color(hex: hex)).padding(5) }
                else { Image(systemName: "plus").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Palette.text2) }
            }
            .frame(width: size - 6, height: size - 6)
            .padding(3)
            .overlay(Circle().strokeBorder(custom ? Palette.ink : .clear, lineWidth: 1.5))
            .scaleEffect(hover && !reduced ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .background(PopupAnchorView(anchor: anchor))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(custom ? .isSelected : [])
    }
}
