import Cocoa
import ImageIO
import UniformTypeIdentifiers

// Einzelpixel (Top-Left-Koordinaten) lesen
func pixelTopLeft(_ cg: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
    guard let c = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return (-1, -1, -1) }
    var buf = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(c, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Int(buf[0]), Int(buf[1]), Int(buf[2]))
}

// Mittlere Farbe eines Bereichs (Top-Left-Koordinaten)
func meanTopLeft(_ cg: CGImage, _ rect: CGRect) -> (Int, Int, Int) {
    guard let crop = cg.cropping(to: rect.integral) else { return (-1, -1, -1) }
    var buf = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .medium
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Int(buf[0]), Int(buf[1]), Int(buf[2]))
}

func lum(_ p: (Int, Int, Int)) -> Int { Int(0.2126 * Double(p.0) + 0.7152 * Double(p.1) + 0.0722 * Double(p.2)) }

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "  ✓ " : "  ✗ ") + msg)
    if !cond { failures += 1 }
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
let sampleURL = tmp.appendingPathComponent("schwaerzen_sample.png")
let outURL = tmp.appendingPathComponent("schwaerzen_out.png")
try? FileManager.default.removeItem(at: outURL)

// Testbild 200×100: linke Hälfte dunkel (0.25 -> ~64), rechte Hälfte hell (0.80 -> ~204)
let W = 200, H = 100
let cs = CGColorSpaceCreateDeviceRGB()
let mk = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                   space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
mk.setFillColor(gray: 0.25, alpha: 1); mk.fill(CGRect(x: 0, y: 0, width: 100, height: 100))   // links dunkel
mk.setFillColor(gray: 0.80, alpha: 1); mk.fill(CGRect(x: 100, y: 0, width: 100, height: 100)) // rechts hell
let sample = mk.makeImage()!
check(writeImage(sample, to: sampleURL, jpeg: false), "Testbild (dunkel|hell) gespeichert")

guard let loaded = loadUpright(sampleURL) else { print("✗ laden fehlgeschlagen"); exit(1) }
check(loaded.cg.width == 200 && loaded.cg.height == 100, "geladen mit 200×100 px")

// Box A in der dunklen Hälfte, Box B in der hellen Hälfte (normalisiert, Ursprung unten-links)
let boxA = CGRect(x: 0.10, y: 0.25, width: 0.30, height: 0.50)  // px x[20,80]  y[25,75]
let boxB = CGRect(x: 0.60, y: 0.25, width: 0.30, height: 0.50)  // px x[120,180] y[25,75]
guard let result = renderRedacted(base: loaded.cg, norms: [boxA, boxB]) else {
    print("✗ renderRedacted fehlgeschlagen"); exit(1)
}
check(writeImage(result, to: outURL, jpeg: false), "Ergebnis gespeichert")
guard let r = loadUpright(outURL)?.cg else { print("✗ Ergebnis nicht ladbar"); exit(1) }

// Mittlere Helligkeit der Box-Innenflächen (Top-Left-Koordinaten)
let meanA = meanTopLeft(r, CGRect(x: 30, y: 35, width: 40, height: 30))
let meanB = meanTopLeft(r, CGRect(x: 130, y: 35, width: 40, height: 30))
let lumA = lum(meanA), lumB = lum(meanB)
print("  Box A (dunkle Umgebung) Ø=\(meanA) Lum=\(lumA)   Box B (helle Umgebung) Ø=\(meanB) Lum=\(lumB)")

// Anpassung: Box folgt der Helligkeit der Umgebung (~64 bzw. ~204)
check((34...104).contains(lumA), "Box A passt sich der dunklen Umgebung an (~64)")
check((164...234).contains(lumB), "Box B passt sich der hellen Umgebung an (~204)")
check(lumB - lumA > 80, "heller Hintergrund -> deutlich helleres Kästchen als bei dunklem")

// Grau (Umgebung ist neutralgrau -> Box bleibt grau)
check(abs(meanA.0 - meanA.1) < 14 && abs(meanA.1 - meanA.2) < 14, "Box A ist grau (kein Farbstich)")

// Melange/Körnung vorhanden: Helligkeit variiert innerhalb der Box
var lo = 999, hi = -1
for yy in stride(from: 30, through: 70, by: 8) {
    for xx in stride(from: 25, through: 75, by: 8) {
        let v = lum(pixelTopLeft(r, xx, yy))
        lo = min(lo, v); hi = max(hi, v)
    }
}
print("  Körnung Box A: Lum-Spanne \(lo)…\(hi)")
check(hi - lo > 12, "Box A ist meliert (sichtbare Körnung, nicht flach)")

// Umgebung unverändert
let outDark = pixelTopLeft(r, 6, 50)
let outLight = pixelTopLeft(r, 194, 50)
check(abs(lum(outDark) - 64) < 10, "dunkle Umgebung bleibt unverändert (~64)")
check(abs(lum(outLight) - 204) < 10, "helle Umgebung bleibt unverändert (~204)")

// Namensschema
let oc = outputURL(for: URL(fileURLWithPath: "/x/Foto.JPG"), jpeg: true)
check(oc.lastPathComponent == "Foto_geschwaerzt.jpg", "Ausgabename: Foto_geschwaerzt.jpg")

print(failures == 0 ? "\nALLE TESTS BESTANDEN ✓" : "\n\(failures) TEST(S) FEHLGESCHLAGEN ✗")
exit(failures == 0 ? 0 : 1)
