import AppKit
import ImageIO
import UniformTypeIdentifiers
// Converts the Orbit icon pack into compact Dock icons on the Apple icon grid.
// Source is each icon's ICNS (the pack's 04_Rarity.png is truncated); its 1024 px tile is full-bleed, so it each is re-masked, placed in the 824 px body with a soft shadow,
// downscaled to 512 px and stored as HEIC with alpha. Three tiles in the pack are cropped from a sheet with a
// neighbour's edge, so they are cut to their own tile first.
// Usage (from macos/): swift scripts/app-icons.swift <Orbit_Icon_Pack folder> Resources/AppIcons
let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let target = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
let crops: [String: ClosedRange<CGFloat>] = ["03_My_Melody": 58...940, "04_Cinnamoroll": 68...892, "05_Pompompurin": 46...862]
let sets = [("01_Base", "base"), ("02_Sonic", "sonic"), ("03_Hello_Kitty", "kitty"), ("04_My_Little_Pony", "pony")]
let output = 512
for (folder, prefix) in sets {
    let files = try FileManager.default.contentsOfDirectory(at: source.appendingPathComponent(folder).appendingPathComponent("ICNS"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "icns" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for file in files {
        let name = file.deletingPathExtension().lastPathComponent
        guard let images = CGImageSourceCreateWithURL(file as CFURL, nil) else { fatalError(file.path) }
        let largest = (0..<CGImageSourceGetCount(images)).compactMap { CGImageSourceCreateImageAtIndex(images, $0, nil) }.max { $0.width < $1.width }
        guard var cg = largest, cg.width == 1024 else { fatalError("no 1024 px image in " + file.path) }
        if let range = crops[name] {
            let width = range.upperBound - range.lowerBound
            let rect = CGRect(x: range.lowerBound, y: (CGFloat(cg.height) - width) / 2, width: width, height: width)
            cg = cg.cropping(to: rect)!
        } else {
            cg = cg.cropping(to: CGRect(x: 8, y: 8, width: cg.width - 16, height: cg.height - 16))!
        }
        let size = CGFloat(output), s = size / 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: output, height: output, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let path = CGPath(roundedRect: body, cornerWidth: 186 * s, cornerHeight: 186 * s, transform: nil)
        // The masked tile is drawn as one layer so the shadow follows its edge without a fill rim underneath.
        let layer = CGContext(data: nil, width: output, height: output, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        layer.interpolationQuality = .high
        layer.addPath(path); layer.clip(); layer.draw(cg, in: body.insetBy(dx: -2, dy: -2))
        context.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: CGColor(gray: 0, alpha: 0.28))
        context.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
        let out = target.appendingPathComponent(prefix + "-" + String(name.drop { $0.isNumber || $0 == "_" }).lowercased().replacingOccurrences(of: "_", with: "-") + ".heic")
        let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.heic.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("heic " + out.path) }
        print(out.lastPathComponent)
    }
}
