import Cocoa
import ImageIO
import UniformTypeIdentifiers

// MARK: - Bild-Helfer (UI-unabhängig, testbar)

/// Körnung des Rauschens (± um den Grundton, 0…1). Sichtbar, aber nicht dominant.
let kNoiseAmp: CGFloat = 0.11

/// Erzeugt einen melierten Rausch-Bitmap um einen Grundton `base` mit Amplitude `amp`.
/// Pro Pixel wird die Helligkeit (gleich auf alle Kanäle) zufällig variiert -> Graustufen-Melange,
/// die einen evtl. leichten Farbstich des Grundtons beibehält.
func makeNoiseRep(_ w: Int, _ h: Int,
                  baseR: CGFloat, baseG: CGFloat, baseB: CGFloat, amp: CGFloat) -> NSBitmapImageRep {
    let W = max(1, w), H = max(1, h)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: W, pixelsHigh: H,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: W * 4, bitsPerPixel: 32)!
    if let p = rep.bitmapData {
        var g = SystemRandomNumberGenerator()
        let count = W * H
        let a = Double(amp)
        let bR = Double(baseR), bG = Double(baseG), bB = Double(baseB)
        for i in 0..<count {
            // dreieckverteilte Abweichung (weicher als Gleichverteilung) im Bereich ±amp
            let d = ((Double.random(in: 0...1, using: &g) + Double.random(in: 0...1, using: &g)) * 0.5 - 0.5) * 2 * a
            let r = min(1, max(0, bR + d))
            let gg = min(1, max(0, bG + d))
            let bb = min(1, max(0, bB + d))
            let o = i * 4
            p[o] = UInt8(r * 255); p[o + 1] = UInt8(gg * 255); p[o + 2] = UInt8(bb * 255); p[o + 3] = 255
        }
    }
    return rep
}

func makeNoiseImage(_ w: Int, _ h: Int,
                    baseR: CGFloat, baseG: CGFloat, baseB: CGFloat, amp: CGFloat) -> NSImage {
    let rep = makeNoiseRep(w, h, baseR: baseR, baseG: baseG, baseB: baseB, amp: amp)
    let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    img.addRepresentation(rep)
    return img
}

func makeNoiseCG(_ w: Int, _ h: Int,
                 baseR: CGFloat, baseG: CGFloat, baseB: CGFloat, amp: CGFloat) -> CGImage? {
    return makeNoiseRep(w, h, baseR: baseR, baseG: baseG, baseB: baseB, amp: amp).cgImage
}

// MARK: - Anpassung an die Umgebung

/// Durchschnittsfarbe (0…1) eines Bildbereichs – via Skalierung auf 1×1 Pixel.
/// `rectPx` in Top-Left-Pixelkoordinaten.
func avgColor(of base: CGImage, in rectPx: CGRect) -> (CGFloat, CGFloat, CGFloat)? {
    let imgBounds = CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height))
    let clamped = rectPx.integral.intersection(imgBounds)
    guard clamped.width >= 1, clamped.height >= 1, let crop = base.cropping(to: clamped) else { return nil }
    var buf = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (CGFloat(buf[0]) / 255, CGFloat(buf[1]) / 255, CGFloat(buf[2]) / 255)
}

/// Mittlere Farbe des Rings DIREKT AUSSERHALB der Box (oben/unten/links/rechts).
/// `norm` ist normalisiert mit Ursprung unten-links.
func ringAverageColor(base: CGImage, norm: CGRect) -> (CGFloat, CGFloat, CGFloat) {
    let W = CGFloat(base.width), H = CGFloat(base.height)
    let px = norm.minX * W
    let pw = norm.width * W
    let pyTop = (1 - norm.maxY) * H            // Top-Left-Ursprung
    let ph = norm.height * H
    let m = max(6, min(pw, ph) * 0.15)         // Ringbreite
    let strips = [
        CGRect(x: px - m, y: pyTop - m, width: pw + 2 * m, height: m),  // oben
        CGRect(x: px - m, y: pyTop + ph, width: pw + 2 * m, height: m), // unten
        CGRect(x: px - m, y: pyTop, width: m, height: ph),             // links
        CGRect(x: px + pw, y: pyTop, width: m, height: ph),            // rechts
    ]
    var rs: CGFloat = 0, gs: CGFloat = 0, bs: CGFloat = 0, n: CGFloat = 0
    for s in strips {
        if let c = avgColor(of: base, in: s) { rs += c.0; gs += c.1; bs += c.2; n += 1 }
    }
    if n == 0 {
        return avgColor(of: base, in: CGRect(x: 0, y: 0, width: W, height: H)) ?? (0.53, 0.53, 0.53)
    }
    return (rs / n, gs / n, bs / n)
}

/// Grundton einer Box: überwiegend Grau auf Helligkeit der Umgebung,
/// plus ein leichter Farbstich (`tint`) der Umgebung, damit es sich einfügt.
func adaptedBase(base: CGImage, norm: CGRect, tint: CGFloat = 0.22) -> (CGFloat, CGFloat, CGFloat) {
    let c = ringAverageColor(base: base, norm: norm)
    let l = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2   // Luminanz
    let r = l * (1 - tint) + c.0 * tint
    let g = l * (1 - tint) + c.1 * tint
    let b = l * (1 - tint) + c.2 * tint
    return (r, g, b)
}

/// Lädt ein Bild in voller Auflösung und wendet die EXIF-Ausrichtung an (aufrecht).
func loadUpright(_ url: URL) -> (cg: CGImage, jpeg: Bool)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
    let ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
    let maxDim = max(pw, ph)
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,                 // Ausrichtung anwenden
        kCGImageSourceThumbnailMaxPixelSize: (maxDim > 0 ? maxDim : 1_000_000)  // volle Auflösung
    ]
    let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    guard let image = cg else { return nil }
    var jpeg = false
    if let t = CGImageSourceGetType(src), let ut = UTType(t as String) {
        jpeg = ut.conforms(to: .jpeg)
    }
    return (image, jpeg)
}

/// Brennt die Schwärzungen dauerhaft ins Bild ein (volle Pixel-Auflösung).
/// `norms` sind normalisierte Rechtecke (0…1) mit Ursprung unten-links.
func renderRedacted(base: CGImage, norms: [CGRect]) -> CGImage? {
    let W = base.width, H = base.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: W, height: H,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(base, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.interpolationQuality = .none
    let bounds = CGRect(x: 0, y: 0, width: W, height: H)
    for n in norms {
        var r = CGRect(x: n.minX * CGFloat(W), y: n.minY * CGFloat(H),
                       width: n.width * CGFloat(W), height: n.height * CGFloat(H)).integral
        r = r.intersection(bounds)
        if r.width < 1 || r.height < 1 { continue }
        let tone = adaptedBase(base: base, norm: n)
        if let noise = makeNoiseCG(Int(r.width), Int(r.height),
                                   baseR: tone.0, baseG: tone.1, baseB: tone.2, amp: kNoiseAmp) {
            ctx.draw(noise, in: r)
        } else {
            ctx.setFillColor(red: tone.0, green: tone.1, blue: tone.2, alpha: 1); ctx.fill(r)
        }
    }
    return ctx.makeImage()
}

func writeImage(_ cg: CGImage, to url: URL, jpeg: Bool) -> Bool {
    let utType = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else { return false }
    var props: [CFString: Any] = [:]
    if jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.95 }
    CGImageDestinationAddImage(dest, cg, props as CFDictionary)        // ohne EXIF -> Metadaten werden entfernt
    return CGImageDestinationFinalize(dest)
}

func outputURL(for src: URL, jpeg: Bool) -> URL {
    let dir = src.deletingLastPathComponent()
    let base = src.deletingPathExtension().lastPathComponent
    let ext = jpeg ? "jpg" : "png"
    let fm = FileManager.default
    var candidate = dir.appendingPathComponent("\(base)_geschwaerzt.\(ext)")
    var i = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = dir.appendingPathComponent("\(base)_geschwaerzt-\(i).\(ext)")
        i += 1
    }
    return candidate
}

func showAlert(_ title: String, _ info: String, style: NSAlert.Style = .informational) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    a.alertStyle = style
    a.addButton(withTitle: "OK")
    a.runModal()
}

func isImageFile(_ url: URL) -> Bool {
    if let ut = UTType(filenameExtension: url.pathExtension) {
        return ut.conforms(to: .image)
    }
    return false
}

// MARK: - App-Name

let kAppName = "Gandalf, der Graubalken"
let kAppSubtitle = "Sensible Bildstellen unkenntlich machen"

// MARK: - Über-Fenster (UI, aber offscreen testbar)

/// Anklickbarer Link-Button (öffnet eine URL, sieht aus wie ein Textlink).
final class LinkButton: NSButton {
    var linkURL: URL?
    init(text: String, url: URL?, size: CGFloat = 15) {
        super.init(frame: .zero)
        self.linkURL = url
        self.isBordered = false
        self.bezelStyle = .inline
        self.setButtonType(.momentaryChange)
        self.focusRingType = .none
        self.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: size),
        ])
        self.target = self
        self.action = #selector(openLink)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openLink() { if let u = linkURL { NSWorkspace.shared.open(u) } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// Baut die Inhalts-View des „Info"-Fensters (analog zur Vorlage).
func makeAboutView(appName: String, subtitle: String, logo: NSImage? = nil) -> NSView {
    let contentWidth: CGFloat = 540
    let pad: CGFloat = 40

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    func wrapping(_ s: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = NSFont.systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.preferredMaxLayoutWidth = contentWidth
        t.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return t
    }

    // CGI-Logo: echtes Bild, falls vorhanden – sonst roter Schriftzug als Fallback
    let logoView: NSView
    if let logo = logo {
        let iv = NSImageView()
        iv.image = logo
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignLeft
        iv.translatesAutoresizingMaskIntoConstraints = false
        let h: CGFloat = 58
        let w = h * (logo.size.width / max(1, logo.size.height))
        NSLayoutConstraint.activate([
            iv.heightAnchor.constraint(equalToConstant: h),
            iv.widthAnchor.constraint(equalToConstant: w),
        ])
        logoView = iv
    } else {
        let t = NSTextField(labelWithString: "CGI")
        t.font = NSFont.systemFont(ofSize: 60, weight: .black)
        t.textColor = NSColor(srgbRed: 0.890, green: 0.098, blue: 0.216, alpha: 1)   // CGI-Rot #E31937
        logoView = t
    }

    let title = wrapping(appName, size: 28, color: .labelColor, weight: .bold)
    let sub = wrapping(subtitle, size: 15, color: .secondaryLabelColor)
    let author = NSTextField(labelWithString: "Katrin Schwabel")
    author.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    let email = LinkButton(text: "katrin.schwabel@cgi.com", url: URL(string: "mailto:katrin.schwabel@cgi.com"))

    let disclaimer = wrapping(
        "Diese App gehört CGI (www.cgi.com/de). Sie ist als reines Freizeitprojekt entstanden und darf nicht an Kunden weitergegeben oder dort eingesetzt werden. Sie ist keine offizielle CGI-IP und wurde nicht durch eine formale Qualitätskontrolle geprüft.",
        size: 13.5, color: .labelColor)

    let usage = wrapping(
        "So funktioniert’s:\n\n1.  Bild laden – über das Menüleisten-Symbol „Bild öffnen …“, per Drag & Drop aufs Symbol, oder „Bild aus der Vorschau laden“.\n\n2.  Mit der Maus Rechtecke über sensible Stellen ziehen – sie werden sofort mit grauem, an die Umgebung angepasstem Rauschen abgedeckt. (⌘Z = letzten entfernen · Esc = abbrechen)\n\n3.  Speichern (⌘S) – legt eine Kopie „…_geschwaerzt“ neben dem Original an. Das Original bleibt unverändert, EXIF-Daten werden entfernt.",
        size: 13.5, color: .labelColor)

    let footer = wrapping(
        "CGI und das CGI-Logo sind Marken/Assets der CGI Inc. bzw. verbundener Unternehmen.",
        size: 11.5, color: .tertiaryLabelColor)

    stack.addArrangedSubview(logoView)
    stack.setCustomSpacing(18, after: logoView)
    stack.addArrangedSubview(title)
    stack.setCustomSpacing(2, after: title)
    stack.addArrangedSubview(sub)
    stack.setCustomSpacing(24, after: sub)
    stack.addArrangedSubview(author)
    stack.setCustomSpacing(1, after: author)
    stack.addArrangedSubview(email)
    stack.setCustomSpacing(24, after: email)
    stack.addArrangedSubview(disclaimer)
    stack.setCustomSpacing(20, after: disclaimer)
    stack.addArrangedSubview(usage)
    stack.setCustomSpacing(24, after: usage)
    stack.addArrangedSubview(footer)

    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad),
        stack.widthAnchor.constraint(equalToConstant: contentWidth),
    ])
    return container
}
