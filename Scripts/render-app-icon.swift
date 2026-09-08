#!/usr/bin/env swift
import AppKit

// Run from any directory: swift Scripts/render-app-icon.swift [output-directory]
// SVGs are the editable masters; PNGs and ICNS are distribution derivatives.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : root.appendingPathComponent("Resources", isDirectory: true)
let source = root.appendingPathComponent("Sources/Nook/Resources/NookAppIcon.svg")
guard let image = NSImage(contentsOf: source) else { fatalError("Cannot load \(source.path)") }
let iconset = output.appendingPathComponent("Nook.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon PNG") }
    try png.write(to: url, options: .atomic)
}
for points in [16, 32, 128, 256, 512] {
    try render(points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(1024, to: output.appendingPathComponent("NookIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("Nook.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Rendered NookIcon.png, Nook.icns and Nook.iconset in \(output.path)")
