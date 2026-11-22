import AppKit

func drawIcon(size: Int) -> Data {
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.clear.setFill()
    bounds.fill()
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 1024)
    scale.concat()
    let design = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let tile = NSBezierPath(roundedRect: design.insetBy(dx: 97, dy: 97), xRadius: 188, yRadius: 188)
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.11, alpha: 1).setFill()
    tile.fill()
    NSColor(srgbRed: 0.19, green: 0.19, blue: 0.19, alpha: 1).setStroke()
    tile.lineWidth = 7
    tile.stroke()

    let check = NSBezierPath()
    check.move(to: CGPoint(x: 330, y: 510))
    check.line(to: CGPoint(x: 458, y: 382))
    check.line(to: CGPoint(x: 703, y: 647))
    check.lineWidth = 79
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1).setStroke()
    check.stroke()
    return bitmap.representation(using: .png, properties: [:])!
}

func sizeField(_ size: Int) -> Data {
    var bigEndian = UInt32(size).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

// The ICNS header and each image record carry their size including the header.
let representations = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                       ("ic08", 256), ("ic09", 512), ("ic10", 1024)]
var images = Data()
for (type, size) in representations {
    let png = drawIcon(size: size)
    images.append(contentsOf: type.utf8)
    images.append(sizeField(png.count + 8))
    images.append(png)
}
var icon = Data("icns".utf8)
icon.append(sizeField(images.count + 8))
icon.append(images)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
