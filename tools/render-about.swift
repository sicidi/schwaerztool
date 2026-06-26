import Cocoa

// Rendert die Über-View (aus Core.swift) offscreen in ein PNG, zur visuellen Prüfung.
final class BgView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
    }
}

@main
struct RenderAbout {
    static func main() {
        let logoPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/cgi-logo.png"
        let logo = NSImage(contentsOfFile: logoPath)
        let about = makeAboutView(appName: kAppName, subtitle: kAppSubtitle, logo: logo)
        let size = about.fittingSize
        about.translatesAutoresizingMaskIntoConstraints = true
        about.frame = NSRect(origin: .zero, size: size)

        let bg = BgView(frame: NSRect(origin: .zero, size: size))
        bg.addSubview(about)
        bg.layoutSubtreeIfNeeded()

        guard let rep = bg.bitmapImageRepForCachingDisplay(in: bg.bounds) else {
            print("Kein Bitmap-Rep"); return
        }
        let appearance = NSAppearance(named: .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            bg.cacheDisplay(in: bg.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("Kein PNG"); return
        }
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/about.png"
        do { try data.write(to: URL(fileURLWithPath: out)); print("✓ \(out)  (\(Int(size.width))×\(Int(size.height)))") }
        catch { print("Fehler: \(error)") }
    }
}
