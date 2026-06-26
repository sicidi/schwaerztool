import Cocoa

// Zeichnet das App-Icon: dunkle Kachel, helle Foto-Karte mit Mini-Szene (Sonne + Berge),
// darüber ein grau-melierter Schwärzungsbalken (echtes Rauschen, via makeNoiseCG aus Core.swift).
func iconRender(_ size: Int) -> CGImage? {
    let s = CGFloat(size) / 1024.0
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(size))   // auf Top-Left-Ursprung umstellen
    ctx.scaleBy(x: 1, y: -1)

    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x*s, y: y*s, width: w*s, height: h*s)
    }
    func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
    }
    func tri(_ p1: (CGFloat, CGFloat), _ p2: (CGFloat, CGFloat), _ p3: (CGFloat, CGFloat)) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: p1.0*s, y: p1.1*s))
        ctx.addLine(to: CGPoint(x: p2.0*s, y: p2.1*s))
        ctx.addLine(to: CGPoint(x: p3.0*s, y: p3.1*s))
        ctx.closePath(); ctx.fillPath()
    }

    // Kachel mit Verlauf
    let tile = R(100, 100, 824, 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185*s, cornerHeight: 185*s, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.243, green: 0.275, blue: 0.337, alpha: 1),
        CGColor(red: 0.118, green: 0.137, blue: 0.169, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()

    // Foto-Karte mit Schatten
    let photo = R(232, 300, 560, 430)
    let photoPath = CGPath(roundedRect: photo, cornerWidth: 44*s, cornerHeight: 44*s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14*s), blur: 40*s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38))
    fill(0.972, 0.980, 0.990)
    ctx.addPath(photoPath); ctx.fillPath()
    ctx.restoreGState()

    // Szene im Foto (geclippt): Himmel, Sonne, Berge
    ctx.saveGState()
    ctx.addPath(photoPath); ctx.clip()
    let sky = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.847, green: 0.910, blue: 0.984, alpha: 1),
        CGColor(red: 0.972, green: 0.980, blue: 0.990, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: photo.minY), end: CGPoint(x: 0, y: photo.maxY), options: [])
    fill(0.965, 0.769, 0.325)                      // Sonne
    ctx.fillEllipse(in: R(300, 348, 120, 120))
    fill(0.255, 0.553, 0.404)                      // Berg hinten
    tri((280, 730), (470, 500), (640, 730))
    fill(0.180, 0.439, 0.318)                      // Berg vorne
    tri((520, 730), (690, 548), (860, 730))
    ctx.restoreGState()

    // Schwärzungsbalken: Schatten, dann graues Rauschen, dann feine Kante
    let bar = R(262, 470, 500, 118)
    let barPath = CGPath(roundedRect: bar, cornerWidth: 22*s, cornerHeight: 22*s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6*s), blur: 22*s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.40))
    fill(0.5, 0.5, 0.5)
    ctx.addPath(barPath); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(barPath); ctx.clip()
    let bw = max(1, Int(bar.width)), bh = max(1, Int(bar.height))
    if let noise = makeNoiseCG(bw, bh, baseR: 0.52, baseG: 0.52, baseB: 0.52, amp: 0.42) {
        ctx.draw(noise, in: bar)
    }
    ctx.restoreGState()
    ctx.addPath(barPath)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
    ctx.setLineWidth(max(1, 2*s))
    ctx.strokePath()

    return ctx.makeImage()
}

@main
struct MakeIcon {
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
        let items: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        for (name, px) in items {
            guard let img = iconRender(px) else { print("FAIL render \(name)"); continue }
            let rep = NSBitmapImageRep(cgImage: img)
            guard let data = rep.representation(using: .png, properties: [:]) else { print("FAIL png \(name)"); continue }
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
            do { try data.write(to: url); print("✓ \(name).png (\(px)px)") }
            catch { print("ERR \(name): \(error)") }
        }
        print("Iconset: \(outDir)")
    }
}
