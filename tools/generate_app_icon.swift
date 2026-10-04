import AppKit

let canvas = NSSize(width: 1024, height: 1024)
let background = NSColor(calibratedRed: 0.965, green: 0.949, blue: 0.902, alpha: 1)
let ink = NSColor(calibratedRed: 0.176, green: 0.255, blue: 0.224, alpha: 1)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon canvas")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
background.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()

let vPath = NSBezierPath()
let centerX: CGFloat = 512
let centerY: CGFloat = 512
let vHeight: CGFloat = 580
let vWidth: CGFloat = 480
let strokeWidth: CGFloat = 120

let topLeft = NSPoint(x: centerX - vWidth/2, y: centerY + vHeight/2)
let bottom = NSPoint(x: centerX, y: centerY - vHeight/2)
let topRight = NSPoint(x: centerX + vWidth/2, y: centerY + vHeight/2)

vPath.move(to: topLeft)
vPath.line(to: bottom)
vPath.line(to: topRight)

vPath.lineWidth = strokeWidth
vPath.lineCapStyle = .round
vPath.lineJoinStyle = .round
ink.setStroke()
vPath.stroke()

NSGraphicsContext.restoreGraphicsState()

guard
    let source = bitmap.cgImage,
    let context = CGContext(
        data: nil,
        width: 1024,
        height: 1024,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else {
    fatalError("Unable to render icon")
}

context.draw(source, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let flattened = context.makeImage() else { fatalError("Unable to flatten icon") }
let outputBitmap = NSBitmapImageRep(cgImage: flattened)
guard let png = outputBitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "VentureIcon.png")
try png.write(to: output, options: .atomic)
