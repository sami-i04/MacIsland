import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tile = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 1.00, green: 0.55, blue: 0.15, alpha: 1),
    NSColor(srgbRed: 0.95, green: 0.30, blue: 0.20, alpha: 1),
])!
gradient.draw(in: tile, angle: -90)

let islandW: CGFloat = 520, islandH: CGFloat = 150
let island = NSRect(x: (size - islandW) / 2, y: rect.maxY - 120 - islandH, width: islandW, height: islandH)
NSColor.black.setFill()
NSBezierPath(roundedRect: island, xRadius: islandH / 2, yRadius: islandH / 2).fill()

let dot: CGFloat = 46
NSColor(srgbRed: 0.18, green: 0.18, blue: 0.24, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: island.maxX - 75 - dot / 2, y: island.midY - dot / 2, width: dot, height: dot)).fill()

let apple = [
    "..........##....",
    ".........###....",
    "........###.....",
    "........##......",
    "...####...####..",
    "..############..",
    ".############...",
    ".###########....",
    ".###########....",
    ".###########....",
    ".############...",
    "..############..",
    "..#############.",
    "...###########..",
    "....####.####...",
    "................",
]
let px: CGFloat = 22
let gridW = px * 16
let originX = (size - gridW) / 2
let originY = rect.minY + 90
NSColor.white.setFill()
for (row, line) in apple.enumerated() {
    for (col, ch) in line.enumerated() where ch == "#" {
        let y = originY + CGFloat(15 - row) * px
        NSRect(x: originX + CGFloat(col) * px, y: y, width: px, height: px).fill()
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
