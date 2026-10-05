import AppKit

// Reproducible original terminal mark. No external artwork or dependencies.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 188, y: 246, width: 648, height: 532), xRadius: 70, yRadius: 70)
frame.lineWidth = 38
frame.stroke()
let prompt = NSBezierPath()
prompt.move(to: NSPoint(x: 310, y: 584))
prompt.line(to: NSPoint(x: 400, y: 502))
prompt.line(to: NSPoint(x: 310, y: 420))
prompt.lineWidth = 42
prompt.lineCapStyle = .round
prompt.lineJoinStyle = .round
prompt.stroke()
let cursor = NSBezierPath()
cursor.move(to: NSPoint(x: 488, y: 420))
cursor.line(to: NSPoint(x: 667, y: 420))
cursor.lineWidth = 42
cursor.lineCapStyle = .round
cursor.stroke()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "Shiplog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
