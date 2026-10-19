import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No bitmap context") }
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 215, yRadius: 215)
NSColor(white: 0.10, alpha: 1).setFill()
background.fill()
NSColor(white: 0.19, alpha: 1).setStroke()
background.lineWidth = 2
background.stroke()

// Original vector mark: one stem splitting into outward diagonal arrows,
// matching the direction and weight of the branch symbol in the sidebar.
// Keep the generous inset and solid silhouette legible at Dock sizes.
NSColor(white: 0.94, alpha: 1).setStroke()
let path = NSBezierPath()
path.lineWidth = 72
path.lineCapStyle = .round
path.lineJoinStyle = .round
path.move(to: NSPoint(x: 512, y: 264))
path.line(to: NSPoint(x: 512, y: 444))
path.curve(to: NSPoint(x: 334, y: 700), controlPoint1: NSPoint(x: 512, y: 554), controlPoint2: NSPoint(x: 450, y: 620))
path.move(to: NSPoint(x: 512, y: 444))
path.curve(to: NSPoint(x: 690, y: 700), controlPoint1: NSPoint(x: 512, y: 554), controlPoint2: NSPoint(x: 574, y: 620))
path.stroke()

NSColor(white: 0.94, alpha: 1).setFill()
for right in [false, true] {
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: right ? 1024 - x : x, y: y)
    }
    let arrow = NSBezierPath()
    arrow.move(to: point(280, 780))
    arrow.line(to: point(390, 780))
    arrow.curve(to: point(400, 755), controlPoint1: point(410, 780), controlPoint2: point(413, 768))
    arrow.line(to: point(285, 640))
    arrow.curve(to: point(260, 650), controlPoint1: point(272, 627), controlPoint2: point(260, 630))
    arrow.line(to: point(260, 760))
    arrow.curve(to: point(280, 780), controlPoint1: point(260, 774), controlPoint2: point(266, 780))
    arrow.close()
    arrow.fill()
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
