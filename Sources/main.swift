import Cocoa
import ImageIO
import UniformTypeIdentifiers

// Bild-Helfer (makeNoise*, loadUpright, renderRedacted, writeImage, outputURL, …) liegen in Core.swift.

// MARK: - Editor-View (Bildanzeige + Rechtecke ziehen)

final class Redaction {
    var norm: CGRect
    let preview: NSImage
    init(norm: CGRect, preview: NSImage) { self.norm = norm; self.preview = preview }
}

final class EditorView: NSView {
    var displayImage: NSImage?
    var baseCG: CGImage?
    var pixelSize: CGSize = .zero
    var redactions: [Redaction] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Rechteck im View, in das das Bild (seitenverhältnistreu) gezeichnet wird.
    func imageFrame() -> CGRect {
        let avail = bounds.insetBy(dx: 12, dy: 12)
        guard pixelSize.width > 0, pixelSize.height > 0,
              avail.width > 0, avail.height > 0 else { return bounds }
        let scale = min(avail.width / pixelSize.width, avail.height / pixelSize.height)
        let w = pixelSize.width * scale
        let h = pixelSize.height * scale
        return CGRect(x: avail.midX - w / 2, y: avail.midY - h / 2, width: w, height: h)
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX),
                y: min(max(p.y, r.minY), r.maxY))
    }

    private func viewRect(for norm: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + norm.minX * frame.width,
               y: frame.minY + norm.minY * frame.height,
               width: norm.width * frame.width,
               height: norm.height * frame.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let img = displayImage else { return }
        let frame = imageFrame()
        img.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1.0)

        for r in redactions {
            let vr = viewRect(for: r.norm, in: frame)
            r.preview.draw(in: vr, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSColor(white: 0.0, alpha: 0.25).setStroke()
            let p = NSBezierPath(rect: vr.insetBy(dx: 0.5, dy: 0.5))
            p.lineWidth = 1
            p.stroke()
        }

        if let s = dragStart, let c = dragCurrent {
            var rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                              width: abs(s.x - c.x), height: abs(s.y - c.y))
            rect = rect.intersection(frame)
            NSColor(white: 0.5, alpha: 0.35).setFill()
            rect.fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1.5
            let dash: [CGFloat] = [5, 3]
            path.setLineDash(dash, count: dash.count, phase: 0)
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = clamp(p, to: imageFrame())
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragCurrent = clamp(p, to: imageFrame())
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil; needsDisplay = true }
        guard let s = dragStart, let c = dragCurrent else { return }
        let frame = imageFrame()
        var rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(s.x - c.x), height: abs(s.y - c.y))
        rect = rect.intersection(frame)
        guard rect.width >= 5, rect.height >= 5, frame.width > 0, frame.height > 0 else { return }
        let norm = CGRect(x: (rect.minX - frame.minX) / frame.width,
                          y: (rect.minY - frame.minY) / frame.height,
                          width: rect.width / frame.width,
                          height: rect.height / frame.height)
        let pw = max(1, min(1600, Int(norm.width * pixelSize.width)))
        let ph = max(1, min(1600, Int(norm.height * pixelSize.height)))
        let tone: (CGFloat, CGFloat, CGFloat) = baseCG.map { adaptedBase(base: $0, norm: norm) } ?? (0.53, 0.53, 0.53)
        let preview = makeNoiseImage(pw, ph, baseR: tone.0, baseG: tone.1, baseB: tone.2, amp: kNoiseAmp)
        redactions.append(Redaction(norm: norm, preview: preview))
    }

    override func cancelOperation(_ sender: Any?) {
        dragStart = nil; dragCurrent = nil; needsDisplay = true
    }

    func removeLast() { if !redactions.isEmpty { redactions.removeLast(); needsDisplay = true } }
    func clearAll() { redactions.removeAll(); needsDisplay = true }
}

// MARK: - Editor-Fenster

final class Editor: NSObject, NSWindowDelegate {
    let window: NSWindow
    let view = EditorView(frame: .zero)
    let sourceURL: URL
    let baseCG: CGImage
    let isJPEG: Bool
    weak var owner: AppDelegate?

    init(url: URL, cg: CGImage, jpeg: Bool) {
        self.sourceURL = url
        self.baseCG = cg
        self.isJPEG = jpeg
        let pixelSize = CGSize(width: cg.width, height: cg.height)

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.85
        let maxH = screen.height * 0.85 - 56
        let scale = min(1, min(maxW / pixelSize.width, maxH / pixelSize.height))
        let cw = max(520, pixelSize.width * scale)
        let ch = max(360, pixelSize.height * scale) + 56

        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: cw, height: ch),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        view.displayImage = NSImage(cgImage: cg, size: pixelSize)
        view.baseCG = cg
        view.pixelSize = pixelSize

        window.title = "Schwärzen – \(url.lastPathComponent)"
        window.subtitle = "\(cg.width) × \(cg.height) px"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 360)

        setupContent()
        window.center()
    }

    private func makeButton(_ title: String, _ action: Selector, key: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.translatesAutoresizingMaskIntoConstraints = false
        if !key.isEmpty {
            b.keyEquivalent = key
            b.keyEquivalentModifierMask = .command
        }
        return b
    }

    private func setupContent() {
        let content = NSView()
        window.contentView = content

        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)

        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        let hint = NSTextField(labelWithString: "Ziehe ein Rechteck über sensible Stellen.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hint)

        let saveBtn = makeButton("Speichern", #selector(saveAction), key: "s")
        let undoBtn = makeButton("Letzten entfernen", #selector(undoAction), key: "z")
        let clearBtn = makeButton("Alle entfernen", #selector(clearAction), key: "")

        let btns = NSStackView(views: [undoBtn, clearBtn, saveBtn])
        btns.spacing = 8
        btns.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(btns)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),

            hint.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            btns.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            btns.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    @objc func saveAction() {
        if view.redactions.isEmpty {
            showAlert("Keine Bereiche markiert",
                      "Ziehe zuerst mit der Maus mindestens ein Rechteck über die sensiblen Stellen.",
                      style: .warning)
            return
        }
        guard let result = renderRedacted(base: baseCG, norms: view.redactions.map { $0.norm }) else {
            showAlert("Fehler", "Das Bild konnte nicht erzeugt werden.", style: .critical)
            return
        }
        let out = outputURL(for: sourceURL, jpeg: isJPEG)
        if !writeImage(result, to: out, jpeg: isJPEG) {
            showAlert("Fehler", "Konnte die Datei nicht speichern:\n\(out.path)", style: .critical)
            return
        }
        let a = NSAlert()
        a.messageText = "Gespeichert"
        a.informativeText = "\(out.lastPathComponent)\nin \(out.deletingLastPathComponent().path)\n\nDie Schwärzung ist fest ins Bild eingebrannt; EXIF-Metadaten wurden entfernt."
        a.alertStyle = .informational
        a.addButton(withTitle: "Im Finder zeigen")
        a.addButton(withTitle: "Fertig")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([out])
        }
    }

    @objc func undoAction() { view.removeLast() }
    @objc func clearAction() { view.clearAll() }

    func windowWillClose(_ notification: Notification) {
        owner?.editorClosed(self)
    }
}

// MARK: - Drag-&-Drop auf das Menüleisten-Symbol

final class DragView: NSView {
    weak var owner: AppDelegate?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { owner?.showMenu() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] else { return false }
        let images = urls.filter { isImageFile($0) }
        guard !images.isEmpty else { return false }
        owner?.openImages(images)
        return true
    }
}

// MARK: - App-Delegate (Menüleiste)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var editors: [Editor] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Schwärzen")
            img?.isTemplate = true
            button.image = img
            let drag = DragView(frame: button.bounds)
            drag.owner = self
            drag.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(drag)
            NSLayoutConstraint.activate([
                drag.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                drag.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                drag.topAnchor.constraint(equalTo: button.topAnchor),
                drag.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
    }

    func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let aboutItem = appMenu.addItem(withTitle: "Über Schwärzen", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let quitItem = appMenu.addItem(withTitle: "Schwärzen beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let openItem = menu.addItem(withTitle: "Bild öffnen …", action: #selector(openDialog), keyEquivalent: "o")
        openItem.target = self
        let prevItem = menu.addItem(withTitle: "Bild aus der Vorschau laden", action: #selector(loadFromPreview), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(.separator())
        let tip = menu.addItem(withTitle: "Tipp: Bild aufs Symbol ziehen", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(.separator())
        let aboutItem = menu.addItem(withTitle: "Über Schwärzen", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        let quitItem = menu.addItem(withTitle: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        }
    }

    @objc func openDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openImages([url])
        }
    }

    @objc func loadFromPreview() {
        guard let path = frontPreviewImagePath(), !path.isEmpty else {
            showAlert("Kein Bild gefunden",
                      "In der Vorschau ist kein Bild geöffnet, oder der Zugriff wurde nicht erlaubt.\n\nDu kannst das Bild auch über „Bild öffnen …“ wählen oder per Drag & Drop aufs Menüleisten-Symbol ziehen.",
                      style: .warning)
            return
        }
        openImages([URL(fileURLWithPath: path)])
    }

    func frontPreviewImagePath() -> String? {
        let source = """
        tell application "Preview"
            if (count of documents) is 0 then return ""
            try
                return (path of front document)
            on error
                return ""
            end try
        end tell
        """
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&err)
        if err != nil { return nil }
        let s = result.stringValue ?? ""
        return s.isEmpty ? nil : s
    }

    func openImages(_ urls: [URL]) {
        var openedAny = false
        for url in urls {
            guard let loaded = loadUpright(url) else { continue }
            let editor = Editor(url: url, cg: loaded.cg, jpeg: loaded.jpeg)
            editor.owner = self
            editors.append(editor)
            editor.show()
            openedAny = true
        }
        if !openedAny {
            showAlert("Konnte Bild nicht öffnen",
                      "Die Datei ist kein unterstütztes Bildformat.", style: .warning)
        }
    }

    func editorClosed(_ editor: Editor) {
        editors.removeAll { $0 === editor }
    }

    @objc func about() {
        let a = NSAlert()
        a.messageText = "Schwärzen"
        a.informativeText = "Kleines Werkzeug zum dauerhaften Unkenntlichmachen sensibler Stellen in Bildern.\n\n1. Bild öffnen (Menü, Drag & Drop aufs Symbol oder aus der Vorschau laden)\n2. Rechtecke über sensible Stellen ziehen\n3. Speichern – es wird eine Kopie mit „_geschwaerzt“ neben dem Original angelegt."
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Start

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
