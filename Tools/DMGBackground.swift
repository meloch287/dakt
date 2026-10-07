import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift DMGBackground.swift output.tiff version\n", stderr)
    exit(1)
}
let size = NSSize(width: 720, height: 540)
let canvas = NSImage(size: size)
let ink = NSColor(srgbRed: 0.09, green: 0.15, blue: 0.13, alpha: 1)
let secondary = NSColor(srgbRed: 0.30, green: 0.39, blue: 0.35, alpha: 1)
let accent = NSColor(srgbRed: 0.18, green: 0.53, blue: 0.39, alpha: 1)

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(scale))
    transform.concat()
    NSColor(srgbRed: 0.94, green: 0.96, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
              font: NSFont, color: NSColor) {
        let string = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color])
        string.draw(in: NSRect(x: x, y: size.height - top - 55, width: width, height: 55))
    }
    text("Dakt", x: 44, top: 32, width: 500, font: .systemFont(ofSize: 42, weight: .semibold), color: ink)
    text("Перетащите приложение в «Программы»", x: 46, top: 88, width: 630,
         font: .systemFont(ofSize: 16, weight: .regular), color: secondary)
    text("MACOS", x: 605, top: 48, width: 90, font: .systemFont(ofSize: 11, weight: .semibold), color: accent)

    NSColor(srgbRed: 0.82, green: 0.87, blue: 0.84, alpha: 1).setStroke()
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 44, y: 400))
    divider.line(to: NSPoint(x: 676, y: 400))
    divider.lineWidth = 1
    divider.stroke()

    accent.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 337, y: 320))
    arrow.line(to: NSPoint(x: 383, y: 320))
    arrow.move(to: NSPoint(x: 371, y: 332))
    arrow.line(to: NSPoint(x: 383, y: 320))
    arrow.line(to: NSPoint(x: 371, y: 308))
    arrow.stroke()

    text("Первый запуск и подключение — в инструкции ниже.", x: 46, top: 326, width: 630,
         font: .systemFont(ofSize: 13, weight: .regular), color: secondary)
    text("ПОДСКАЗКА В НУЖНЫЙ МОМЕНТ", x: 44, top: 513, width: 520,
         font: .systemFont(ofSize: 9, weight: .medium), color: secondary)
    text("v" + CommandLine.arguments[2], x: 616, top: 509, width: 75,
         font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: secondary)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    canvas.addRepresentation(bitmap)
}
guard let data = canvas.tiffRepresentation else { exit(1) }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
