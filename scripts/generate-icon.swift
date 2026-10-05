import AppKit

// Run from the repository root. The generated icon master is retained unchanged;
// the companion vector follows its folded S silhouette without raster artifacts.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let files = FileManager.default
let dimension: CGFloat = 1254
let path = CGMutablePath()
var svgCommands: [String] = []

func move(_ x: CGFloat, _ y: CGFloat) {
    path.move(to: CGPoint(x: x, y: y))
    svgCommands.append("M \(x) \(y)")
}
func line(_ x: CGFloat, _ y: CGFloat) {
    path.addLine(to: CGPoint(x: x, y: y))
    svgCommands.append("L \(x) \(y)")
}
func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
    path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    svgCommands.append("C \(x1) \(y1) \(x2) \(y2) \(x) \(y)")
}

move(879, 261)
curve(895, 255, 906, 265, 906, 281)
line(906, 416)
curve(906, 439, 894, 451, 871, 459)
line(614, 542)
line(519, 506)
line(519, 528)
curve(519, 545, 523, 550, 540, 557)
line(861, 677)
curve(891, 689, 906, 712, 906, 742)
line(906, 797)
curve(906, 825, 892, 841, 865, 851)
line(396, 1000)
curve(372, 1008, 350, 994, 350, 969)
line(350, 875)
curve(350, 853, 364, 836, 386, 829)
line(583, 761)
line(700, 805)
line(700, 796)
curve(700, 780, 694, 774, 676, 767)
line(394, 662)
curve(365, 652, 350, 633, 350, 607)
line(350, 493)
curve(350, 459, 370, 434, 406, 421)
line(879, 261)
path.closeSubpath()
svgCommands.append("Z")

enum BrandExportError: Error {
    case invalidImage(String)
    case encodingFailed
}

func write(_ data: Data, to name: String) throws {
    let url = root.appendingPathComponent(name)
    try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    print("Exported \(name)")
}

func rasterPNG(image: NSImage, size: Int, transparent: Bool) throws -> Data {
    let alpha = transparent ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let bitmap = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: colorSpace, bitmapInfo: alpha.rawValue),
        let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { throw BrandExportError.encodingFailed }
    bitmap.interpolationQuality = .high
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    if !transparent {
        bitmap.setFillColor(CGColor(srgbRed: 16 / 255, green: 17 / 255, blue: 19 / 255, alpha: 1))
        bitmap.fill(bounds)
    }
    bitmap.draw(source, in: bounds)
    guard let result = bitmap.makeImage(),
        let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
    else { throw BrandExportError.encodingFailed }
    return data
}

// A PDF keeps the canonical logo scalable in Apple's asset catalog.
let pdf = NSMutableData()
var page = CGRect(x: 0, y: 0, width: dimension, height: dimension)
guard let consumer = CGDataConsumer(data: pdf),
    let context = CGContext(consumer: consumer, mediaBox: &page, nil)
else { throw BrandExportError.encodingFailed }
context.beginPDFPage(nil)
context.translateBy(x: 0, y: dimension)
context.scaleBy(x: 1, y: -1)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.addPath(path)
context.fillPath()
context.endPDFPage()
context.closePDF()
let pdfData = pdf as Data
try write(pdfData, to: "brand/exports/shiplog-symbol.pdf")
try write(pdfData, to: "Shiplog/Resources/Assets.xcassets/ShiplogSymbol.imageset/shiplog-symbol.pdf")

// The source and export share precisely the same path as the native PDF.
let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1254 1254" fill="currentColor">
      <title>Shiplog</title>
      <path d="\(svgCommands.joined(separator: " "))"/>
    </svg>
    """
try write(Data(svg.utf8), to: "brand/source/shiplog-symbol.svg")
try write(Data(svg.utf8), to: "brand/exports/shiplog-symbol.svg")

guard let iconImage = NSImage(contentsOf: root.appendingPathComponent("brand/source/shiplog-icon-master.png")),
    let symbolImage = NSImage(data: pdfData)
else { throw BrandExportError.invalidImage("Brand master") }
let icon = try rasterPNG(image: iconImage, size: 1024, transparent: false)
try write(icon, to: "brand/exports/shiplog-app-icon.png")
try write(icon, to: "Shiplog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let preview = try rasterPNG(image: iconImage, size: 256, transparent: false)
try write(preview, to: "Shiplog/Resources/Assets.xcassets/ShiplogIcon.imageset/shiplog-icon.png")
let symbol = try rasterPNG(image: symbolImage, size: 1024, transparent: true)
try write(symbol, to: "brand/exports/shiplog-symbol.png")
