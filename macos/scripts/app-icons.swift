import AppKit
import ImageIO
import UniformTypeIdentifiers

// Package the owner's regenerated Orbit icons. The PNGs are kept outside the repository.
// Usage: swift macos/scripts/app-icons.swift <Orbit_Icon_Pack> <HEIC output> <PNG staging>
// The bounds describe the solid tile in each 1254px image, excluding generated edge debris.
struct Icon {
    let id: String, path: String
    let left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat
}
let icons: [Icon] = [
    Icon(id: "base-original", path: "Стандартные обновлённые/01-исходная.png", left: 10, right: 1243, top: 10, bottom: 1242),
    Icon(id: "base-light", path: "Стандартные обновлённые/02-светлая.png", left: 14, right: 1236, top: 9, bottom: 1243),
    Icon(id: "base-dark", path: "Стандартные обновлённые/03-тёмная.png", left: 11, right: 1239, top: 5, bottom: 1248),
    Icon(id: "base-cream", path: "Стандартные обновлённые/04-кремовая.png", left: 10, right: 1218, top: 11, bottom: 1244),
    Icon(id: "base-purple", path: "Стандартные обновлённые/05-фиолетовая.png", left: 10, right: 1239, top: 10, bottom: 1244),
    Icon(id: "base-blue", path: "Стандартные обновлённые/06-голубая.png", left: 9, right: 1236, top: 10, bottom: 1241),
    Icon(id: "base-pink", path: "Стандартные обновлённые/07-розовая.png", left: 10, right: 1233, top: 9, bottom: 1245),
    Icon(id: "base-red-neon", path: "Стандартные обновлённые/08-красный-неон.png", left: 4, right: 1249, top: 2, bottom: 1249),
    Icon(id: "sonic-sonic", path: "Персонажи обновлённые/Sonic/01-Sonic.png", left: 8, right: 1243, top: 11, bottom: 1243),
    Icon(id: "sonic-tails", path: "Персонажи обновлённые/Sonic/02-Tails.png", left: 32, right: 1213, top: 8, bottom: 1240),
    Icon(id: "sonic-knuckles", path: "Персонажи обновлённые/Sonic/03-Knuckles.png", left: 42, right: 1200, top: 17, bottom: 1237),
    Icon(id: "sonic-amy", path: "Персонажи обновлённые/Sonic/04-Amy.png", left: 39, right: 1203, top: 13, bottom: 1240),
    Icon(id: "sonic-shadow", path: "Персонажи обновлённые/Sonic/05-Shadow.png", left: 31, right: 1217, top: 6, bottom: 1246),
    Icon(id: "kitty-hello-kitty", path: "Персонажи обновлённые/Hello Kitty/01-Hello-Kitty.png", left: 32, right: 1205, top: 23, bottom: 1229),
    Icon(id: "kitty-kuromi", path: "Персонажи обновлённые/Hello Kitty/02-Kuromi.png", left: 33, right: 1203, top: 23, bottom: 1238),
    Icon(id: "kitty-my-melody", path: "Персонажи обновлённые/Hello Kitty/03-My-Melody.png", left: 54, right: 1179, top: 19, bottom: 1233),
    Icon(id: "kitty-cinnamoroll", path: "Персонажи обновлённые/Hello Kitty/04-Cinnamoroll.png", left: 121, right: 1126, top: 128, bottom: 1142),
    Icon(id: "kitty-pompompurin", path: "Персонажи обновлённые/Hello Kitty/05-Pompompurin.png", left: 47, right: 1193, top: 31, bottom: 1228),
    Icon(id: "pony-twilight-sparkle", path: "Персонажи обновлённые/My Little Pony/01-Twilight-Sparkle.png", left: 9, right: 1240, top: 24, bottom: 1227),
    Icon(id: "pony-rainbow-dash", path: "Персонажи обновлённые/My Little Pony/02-Rainbow-Dash.png", left: 11, right: 1238, top: 26, bottom: 1228),
    Icon(id: "pony-pinkie-pie", path: "Персонажи обновлённые/My Little Pony/03-Pinkie-Pie.png", left: 11, right: 1239, top: 22, bottom: 1223),
    Icon(id: "pony-rarity", path: "Персонажи обновлённые/My Little Pony/04-Rarity.png", left: 13, right: 1232, top: 27, bottom: 1223),
    Icon(id: "pony-applejack", path: "Персонажи обновлённые/My Little Pony/05-Applejack.png", left: 16, right: 1233, top: 33, bottom: 1221),
    Icon(id: "pony-fluttershy", path: "Персонажи обновлённые/My Little Pony/06-Fluttershy.png", left: 13, right: 1238, top: 24, bottom: 1229),
]
guard CommandLine.arguments.count == 4 else { fatalError("Expected source, HEIC output and PNG staging folders") }
let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let heicOutput = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let pngOutput = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
for dir in [heicOutput, pngOutput] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
let size = 512
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func context() -> CGContext {
    let result = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    result.interpolationQuality = .high
    return result
}
func write(_ image: CGImage, to url: URL, type: UTType, options: CFDictionary? = nil) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { fatalError(url.path) }
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { fatalError(url.path) }
}
for icon in icons {
    let url = source.appendingPathComponent(icon.path)
    guard let input = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil), image.width == 1254, image.height == 1254 else { fatalError("Invalid source: " + url.path) }
    // A square inset keeps the generated rim outside the final mask without distorting the illustration.
    let side = min(icon.right - icon.left, icon.bottom - icon.top) - 20
    let crop = CGRect(x: (icon.left + icon.right - side) / 2, y: (icon.top + icon.bottom - side) / 2, width: side, height: side).integral
    guard let tile = image.cropping(to: crop) else { fatalError("Cannot crop " + icon.id) }
    let body = CGRect(x: 50, y: 50, width: 412, height: 412)
    let layer = context()
    layer.addPath(CGPath(roundedRect: body, cornerWidth: 94, cornerHeight: 94, transform: nil))
    layer.clip()
    layer.draw(tile, in: body.insetBy(dx: -1, dy: -1))
    let output = context()
    output.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: CGColor(gray: 0, alpha: 0.28))
    output.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
    let result = output.makeImage()!
    write(result, to: pngOutput.appendingPathComponent(icon.id + ".png"), type: .png)
    write(result, to: heicOutput.appendingPathComponent(icon.id + ".heic"), type: .heic, options: [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    print(icon.id)
}
