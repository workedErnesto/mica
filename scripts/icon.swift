import AppKit
// Draws mica's app icon at every size macOS needs: a warm stone tile with three stacked sheets of mica.
// Usage: swift scripts/icon.swift build/mica.iconset && iconutil -c icns build/mica.iconset -o Resources/App/mica.icns
let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha) }
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let s = CGFloat(pixels) / 1024
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // Apple icon grid: 824 pt body inside 1024, with a soft drop shadow.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tile = NSBezierPath(roundedRect: body, xRadius: 186 * s, yRadius: 186 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = color(0x000000, 0.28); shadow.shadowBlurRadius = 24 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s); shadow.set()
    color(0x1C1917).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x3A3532), ending: color(0x161312))!.draw(in: tile, angle: -90)
    // Three translucent sheets, offset like cleaved mica.
    let sheets: [(CGFloat, CGFloat, UInt32, CGFloat)] = [(-92, 96, 0xA8A29E, 0.55), (0, 0, 0xD6D3D1, 0.78), (92, -96, 0xFAFAF9, 0.97)]
    for (dx, dy, hex, alpha) in sheets {
        let rect = NSRect(x: (312 + dx) * s, y: (352 + dy) * s, width: 400 * s, height: 320 * s)
        let sheet = NSBezierPath(roundedRect: rect, xRadius: 64 * s, yRadius: 64 * s)
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow(); lift.shadowColor = color(0x000000, 0.35); lift.shadowBlurRadius = 30 * s; lift.shadowOffset = NSSize(width: 0, height: -12 * s); lift.set()
        color(hex, alpha).setFill(); sheet.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    // Hairline rim keeps the tile readable on dark Docks.
    color(0xFFFFFF, 0.08).setStroke(); tile.lineWidth = max(1, 3 * s); tile.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent(name + ".png"))
}
