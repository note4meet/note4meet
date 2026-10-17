import AppKit
// Erzeugt Support/AppIcon.icns (Kalenderblatt mit Notiz-Symbol)
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let set = URL(fileURLWithPath: "Support/AppIcon.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let r = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let path = NSBezierPath(roundedRect: r, xRadius: s*0.18, yRadius: s*0.18)
    NSGradient(starting: NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1), ending: NSColor(red: 0.12, green: 0.28, blue: 0.75, alpha: 1))!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s*0.42, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = sym.size
        sym.draw(in: NSRect(x: (s-sz.width)/2, y: (s-sz.height)/2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for px in sizes where px <= 512 {
    try! render(px).write(to: set.appendingPathComponent("icon_\(px)x\(px).png"))
    try! render(px*2).write(to: set.appendingPathComponent("icon_\(px)x\(px)@2x.png"))
}
