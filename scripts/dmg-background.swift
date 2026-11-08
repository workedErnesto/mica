import AppKit

let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// A hand-drawn loop guides the eye between the two Finder icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 252, y: 230))
arrow.curve(to: NSPoint(x: 395, y: 257), controlPoint1: NSPoint(x: 305, y: 179), controlPoint2: NSPoint(x: 407, y: 183))
arrow.curve(to: NSPoint(x: 338, y: 268), controlPoint1: NSPoint(x: 384, y: 321), controlPoint2: NSPoint(x: 313, y: 318))
arrow.curve(to: NSPoint(x: 463, y: 229), controlPoint1: NSPoint(x: 359, y: 221), controlPoint2: NSPoint(x: 412, y: 208))
let lift = AffineTransform(translationByX: 0, byY: 48)
arrow.transform(using: lift)
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.lineWidth = 14
NSColor(calibratedWhite: 0.19, alpha: 1).setStroke(); arrow.stroke()
arrow.lineWidth = 8
NSColor(calibratedRed: 0.67, green: 0.65, blue: 0.75, alpha: 1).setStroke(); arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 444, y: 249)); head.line(to: NSPoint(x: 466, y: 229)); head.line(to: NSPoint(x: 438, y: 218))
head.transform(using: lift)
head.lineCapStyle = .round; head.lineJoinStyle = .round; head.lineWidth = 14
NSColor(calibratedWhite: 0.19, alpha: 1).setStroke(); head.stroke()
head.lineWidth = 8
NSColor(calibratedRed: 0.67, green: 0.65, blue: 0.75, alpha: 1).setStroke(); head.stroke()

let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
func label(_ text: String, y: CGFloat, size: CGFloat, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph]
    (text as NSString).draw(in: NSRect(x: 30, y: y, width: 660, height: 28), withAttributes: attributes)
}
label("Перетащите mica в «Программы»", y: 138, size: 17, color: NSColor(calibratedWhite: 0.22, alpha: 1))
label("Drag mica to Applications", y: 110, size: 14, color: NSColor(calibratedWhite: 0.40, alpha: 1))
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("background render failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
