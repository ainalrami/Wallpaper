// Renders Resources/AppIcon.icns: a gradient rounded square with an SF Symbol.
// Usage: swiftly run swiftc scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the shape fills ~80% of the canvas.
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.30, blue: 0.90, alpha: 1),
    ])!.draw(in: shape, angle: -60)

    let configuration = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let symbolSize = symbol.size
        symbol.draw(in: NSRect(
            x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2,
            width: symbolSize.width, height: symbolSize.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
