import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No bitmap context") }
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 215, yRadius: 215)
NSColor(white: 0.10, alpha: 1).setFill(); background.fill()
NSColor(white: 0.92, alpha: 1).setStroke()
let path = NSBezierPath(); path.lineWidth = 78; path.lineCapStyle = .round; path.lineJoinStyle = .round
path.move(to: NSPoint(x: 512, y: 264)); path.line(to: NSPoint(x: 512, y: 480))
path.curve(to: NSPoint(x: 724, y: 728), controlPoint1: NSPoint(x: 512, y: 610), controlPoint2: NSPoint(x: 650, y: 620))
path.move(to: NSPoint(x: 512, y: 480)); path.curve(to: NSPoint(x: 300, y: 728), controlPoint1: NSPoint(x: 512, y: 610), controlPoint2: NSPoint(x: 374, y: 620)); path.stroke()
NSColor(white: 0.92, alpha: 1).setFill()
for x in [300.0, 724.0] {
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: x, y: 800)); arrow.line(to: NSPoint(x: x - 90, y: 675)); arrow.line(to: NSPoint(x: x + 90, y: 675)); arrow.close(); arrow.fill()
}
guard let image = context.makeImage() else { fatalError("No icon") }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: NSSize(width: 1024, height: 1024)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
