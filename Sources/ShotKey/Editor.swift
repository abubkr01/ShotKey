import AppKit
import ScreenCaptureKit
import CoreImage
import Vision

enum EditorTool: String, CaseIterable, Codable {
    case select, arrow, line, rectangle, ellipse, text, blur, crop, picker, ocr
    var label: String {
        switch self {
        case .select: return "Select V"
        case .arrow: return "Arrow A"
        case .line: return "Line L"
        case .rectangle: return "Rectangle R"
        case .ellipse: return "Ellipse E"
        case .text: return "Text T"
        case .blur: return "Blur B"
        case .crop: return "Crop C"
        case .picker: return "Pick color I"
        case .ocr: return "Copy text O"
        }
    }
    static func key(_ key: String) -> EditorTool? {
        ["v": .select, "a": .arrow, "l": .line, "r": .rectangle,
         "e": .ellipse, "t": .text, "b": .blur, "c": .crop, "i": .picker, "o": .ocr][key]
    }
}

struct EditorColor: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .systemRed
        r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent
    }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

struct EditorStyle: Codable, Equatable {
    var color = EditorColor(.systemRed)
    var fill = EditorColor(.black)
    var width: Double = 3
    var fillMode = 0 // outline, fill, both
    var fontSize: Double = 28
    var textBackground = false
    var textOutline: Double = 0
    var outline = EditorColor(.black)
    var blur: Double = 14

    static func load(_ tool: EditorTool, defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "editor.style." + tool.rawValue),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(_ tool: EditorTool, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: "editor.style." + tool.rawValue)
        }
    }
}

struct Annotation: Equatable {
    var id = UUID()
    var tool: EditorTool
    var start: CGPoint
    var end: CGPoint
    var style: EditorStyle
    var text = ""
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    mutating func move(_ delta: CGPoint) {
        start.x += delta.x; start.y += delta.y
        end.x += delta.x; end.y += delta.y
    }
}

struct EditorState: Equatable {
    var annotations: [Annotation] = []
    var crop: CGRect?
}

/// History stores vector edits and crop rectangles; the original bitmap is shared.
final class EditorDocument {
    let image: CGImage
    let size: CGSize
    private(set) var state = EditorState()
    private(set) var undoStates: [EditorState] = []
    private(set) var redoStates: [EditorState] = []
    init(image: CGImage, size: CGSize) { self.image = image; self.size = size }
    func commit(_ next: EditorState) {
        guard next != state else { return }
        undoStates.append(state); state = next; redoStates.removeAll()
    }
    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(state); state = previous
    }
    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(state); state = next
    }
    var fullRect: CGRect { CGRect(origin: .zero, size: size) }
    var cropRect: CGRect { state.crop ?? fullRect }
    func render(cropped: Bool = false, excluding: UUID? = nil) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(image.width) / size.width, y: CGFloat(image.height) / size.height)
        context.draw(image, in: fullRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in state.annotations {
            if annotation.id == excluding { continue }
            if annotation.tool == .blur {
                // Blur the composition up to this layer, including earlier annotations.
                if let current = context.makeImage() {
                    let input = CIImage(cgImage: current)
                    let scale = CGFloat(image.width) / size.width
                    let filtered = input.clampedToExtent().applyingFilter("CIGaussianBlur",
                        parameters: [kCIInputRadiusKey: annotation.style.blur * scale]).cropped(to: input.extent)
                    if let blurred = Self.ciContext.createCGImage(filtered, from: input.extent) {
                        context.saveGState()
                        context.clip(to: annotation.rect)
                        context.draw(blurred, in: fullRect)
                        context.restoreGState()
                    }
                }
            } else { Self.draw(annotation) }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { return nil }
        guard cropped, let crop = state.crop else { return result }
        let sx = CGFloat(image.width) / size.width, sy = CGFloat(image.height) / size.height
        let pixelRect = CGRect(x: crop.minX * sx, y: (size.height - crop.maxY) * sy,
                               width: crop.width * sx, height: crop.height * sy).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result.cropping(to: pixelRect)
    }
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func draw(_ a: Annotation) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let s = a.style
        s.color.ns.setStroke()
        let path: NSBezierPath
        switch a.tool {
        case .rectangle: path = NSBezierPath(rect: a.rect)
        case .ellipse: path = NSBezierPath(ovalIn: a.rect)
        case .arrow, .line:
            path = NSBezierPath()
            path.move(to: a.start); path.line(to: a.end)
            if a.tool == .arrow {
                let angle = atan2(a.end.y - a.start.y, a.end.x - a.start.x)
                let length = max(12, s.width * 4)
                for offset in [-0.5, 0.5] {
                    path.move(to: a.end)
                    path.line(to: CGPoint(x: a.end.x - cos(angle + offset) * length,
                                          y: a.end.y - sin(angle + offset) * length))
                }
            }
        case .text:
            let font = NSFont.systemFont(ofSize: s.fontSize, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: s.color.ns, .paragraphStyle: paragraph
            ]
            if s.textBackground {
                s.fill.ns.setFill()
                NSBezierPath(roundedRect: a.rect, xRadius: 7, yRadius: 7).fill()
            }
            (a.text as NSString).draw(with: a.rect.insetBy(dx: 8, dy: 6),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            return
        default: return
        }
        path.lineWidth = s.width
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        if a.tool == .rectangle || a.tool == .ellipse {
            if s.fillMode != 0 { s.fill.ns.setFill(); path.fill() }
            if s.fillMode != 1 { s.color.ns.setStroke(); path.stroke() }
        } else { path.stroke() }
    }
}

final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// There is one session, including during asynchronous snapshot acquisition.
final class EditorSession: NSObject, NSWindowDelegate {
    static let shared = EditorSession()
    enum Phase { case idle, loading, editing, finishing }
    private struct SavedEdit {
        let window: EditorWindow
        let canvas: EditorCanvas
        let toolbar: EditorToolbar
        let documents: [CGDirectDisplayID: EditorDocument]
        let screens: [CGDirectDisplayID: NSScreen]
        let activeID: CGDirectDisplayID?
        let clipboardSession: Bool
        let quickSelectionActive: Bool
    }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
    private var clipboardSession = false
    private var ocrRequest = UUID()
    private var quickSelectionActive = false
    private var lastEdit: SavedEdit?
    var hasLastEdit: Bool { lastEdit != nil }
    var outputMode: OutputMode {
        get { clipboardSession ? Preferences.shared.clipboardOutputMode : Preferences.shared.outputMode }
        set {
            if clipboardSession { Preferences.shared.clipboardOutputMode = newValue }
            else { Preferences.shared.outputMode = newValue }
        }
    }
    func requestCancel() {
        suspend()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { requestCancel(); return false }
    func openClipboard(pasteboard: NSPasteboard = .general) {
        guard !isActive else {
            window?.makeKeyAndOrderFront(nil)
            canvas?.showMessage("Finish or hide the current edit before opening another image")
            return
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            AppDelegate.shared?.showErrorMessage("The clipboard does not contain an image. Copy an image first.")
            return
        }
        clipboardSession = true; phase = .editing; generation = UUID()
        let document = EditorDocument(image: cg, size: CGSize(width: cg.width, height: cg.height))
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let size = CGSize(width: min(1100, visible.width - 60), height: min(800, visible.height - 60))
        let win = EditorWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        win.title = "ShotKey — Clipboard Image"; win.isReleasedWhenClosed = false
        win.minSize = CGSize(width: 420, height: 300); win.delegate = self
        let scroll = NSScrollView(frame: CGRect(origin: .zero, size: size))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.02; scroll.maxMagnification = 8
        let view = EditorCanvas(document: document); view.frame = document.fullRect
        scroll.documentView = view
        win.contentView = scroll; window = win; canvas = view
        let bar = EditorToolbar(canvas: view, session: self); toolbar = bar
        wire(view, bar)
        installMonitor()
        win.center()
        #if !EDITOR_TESTS
        NSApp.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil)
        #endif
        scroll.magnification = min(1, min((size.width - 30) / document.size.width, (size.height - 80) / document.size.height))
        win.makeFirstResponder(view); view.choose(.select)
        bar.show(screen: win.screen ?? NSScreen.main!, parent: win)
        view.showMessage("Clipboard image · ⌘↩ exports · output: " + outputMode.title)
    }
    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.phase == .loading && event.keyCode == 53 { self.cancel(); return nil }
            if self.phase == .editing { return self.handleKey(event) ? nil : event }
            return event
        }
    }
    func windowDidResize(_ notification: Notification) {
        guard clipboardSession, let window, let screen = window.screen else { return }
        toolbar?.show(screen: screen, parent: window)
    }
    private func wire(_ view: EditorCanvas, _ bar: EditorToolbar) {
        view.onChange = { [weak bar] in bar?.refresh() }
        view.onOCR = { [weak self] rect in self?.recognize(rect) }
        view.onMenu = { [weak bar] in bar?.actionMenu() }
        view.onQuickCrop = { [weak self] in self?.finish(mode: Preferences.shared.quickSelectionOutputMode) }
        view.onToolChosen = { [weak self, weak view] in
            self?.quickSelectionActive = false
            view?.quickCropOnRelease = false
        }
    }
    func recognize(_ rect: CGRect? = nil) {
        guard let canvas, let image = canvas.document.render() else { return }
        let area = rect ?? canvas.document.cropRect
        let sx = CGFloat(image.width) / canvas.document.size.width
        let sy = CGFloat(image.height) / canvas.document.size.height
        let pixels = CGRect(x: area.minX * sx, y: (canvas.document.size.height - area.maxY) * sy,
                            width: area.width * sx, height: area.height * sy).integral
        guard let selection = image.cropping(to: pixels) else { return }
        let token = generation
        ocrRequest = UUID()
        let requestToken = ocrRequest
        canvas.showMessage("Reading text…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> String in
                try EditorOCR.recognize(selection)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.ocrRequest == requestToken, self.phase == .editing else { return }
                switch result {
                case .success(let text):
                    if text.isEmpty { self.canvas?.showMessage("No text found in that area"); return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.canvas?.showMessage("Text copied — line breaks preserved")
                case .failure(let error): self.canvas?.showMessage("Could not read text: " + error.localizedDescription)
                }
            }
        }
    }
    private var generation = UUID()
    private var documents: [CGDirectDisplayID: EditorDocument] = [:]
    private var screens: [CGDirectDisplayID: NSScreen] = [:]
    private var activeID: CGDirectDisplayID?
    private var window: EditorWindow?
    private var canvas: EditorCanvas?
    private var toolbar: EditorToolbar?
    private var timer: Timer?
    private var monitor: Any?
    var snapshotSource: ([(CGDirectDisplayID, NSScreen)]) async throws -> [CGDirectDisplayID: CGImage] = EditorSession.captureSnapshots

    static func captureSnapshots(_ candidates: [(CGDirectDisplayID, NSScreen)]) async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return await withTaskGroup(of: (CGDirectDisplayID, CGImage?).self) { group in
            for (id, _) in candidates {
                guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = CGDisplayPixelsWide(id)
                    config.height = CGDisplayPixelsHigh(id)
                    config.showsCursor = false; config.capturesAudio = false
                    return (id, try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
                }
            }
            var results: [CGDirectDisplayID: CGImage] = [:]
            for await (id, image) in group {
                if let image { results[id] = image }
            }
            return results
        }
    }

    func toggle() {
        switch phase {
        case .loading, .finishing: return
        case .editing: return
        case .idle: begin()
        }
    }
    private func begin() {
        phase = .loading
        generation = UUID()
        let token = generation
        clipboardSession = false
        quickSelectionActive = true
        installMonitor()
        let candidates = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        }
        Task { @MainActor in
            do {
                let snapshots = try await snapshotSource(candidates)
                guard self.generation == token, self.phase == .loading else { return }
                for (id, screen) in candidates {
                    if let image = snapshots[id] {
                        self.documents[id] = EditorDocument(image: image, size: screen.frame.size)
                        self.screens[id] = screen
                    }
                }
                guard let id = self.pointerDisplay() ?? self.documents.keys.first else {
                    throw NSError(domain: "ShotKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display is available."])
                }
                self.phase = .editing
                self.show(id)
                self.startTracking()
                NotificationCenter.default.addObserver(self, selector: #selector(self.cancel),
                    name: NSApplication.didChangeScreenParametersNotification, object: nil)
            } catch {
                guard self.generation == token else { return }
                self.cancel()
                if !CGPreflightScreenCaptureAccess() {
                    _ = CGRequestScreenCaptureAccess()
                    AppDelegate.shared?.showErrorMessage("Screen Recording permission is required. Quit and reopen ShotKey after granting access.")
                } else { AppDelegate.shared?.showError(error) }
            }
        }
    }
    private func pointerDisplay() -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        return screens.first(where: { $0.value.frame.contains(point) })?.key
    }
    @objc private func followPointer() {
        guard phase == .editing, canvas?.isInteracting == false,
              NSColorPanel.shared.isVisible == false,
              let id = pointerDisplay(), id != activeID else { return }
        show(id)
    }
    private func startTracking() {
        timer = Timer(timeInterval: 0.06, target: self, selector: #selector(followPointer), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func show(_ id: CGDirectDisplayID) {
        guard let document = documents[id], let screen = screens[id] else { return }
        let previousTool = canvas?.tool ?? .crop
        canvas?.commitText()
        toolbar?.close()
        window?.close()
        activeID = id
        let newWindow = EditorWindow(contentRect: CGRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        newWindow.setFrame(screen.frame, display: true)
        newWindow.title = "ShotKey Frozen Editor"
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.isReleasedWhenClosed = false
        let newCanvas = EditorCanvas(document: document)
        newCanvas.frame = CGRect(origin: .zero, size: screen.frame.size)
        newCanvas.autoresizingMask = [.width, .height]
        newWindow.contentView = newCanvas
        window = newWindow; canvas = newCanvas
        #if !EDITOR_TESTS
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        #endif
        newWindow.makeFirstResponder(newCanvas)
        newCanvas.quickCropOnRelease = quickSelectionActive
        newCanvas.choose(previousTool, userInitiated: false)
        let newToolbar = EditorToolbar(canvas: newCanvas, session: self)
        toolbar = newToolbar
        wire(newCanvas, newToolbar)
        newToolbar.show(screen: screen, parent: newWindow)
    }
    func finish(mode: OutputMode? = nil) {
        guard phase == .editing, let canvas else { return }
        canvas.commitText()
        canvas.applyCrop()
        phase = .finishing
        guard let result = canvas.document.render(cropped: true) else {
            phase = .editing
            AppDelegate.shared?.showErrorMessage("The edited image could not be rendered. Your edits are still open.")
            return
        }
        if CaptureService.shared.deliverOnMain(result, mode: mode ?? outputMode) { cancel() }
        else { phase = .editing }
    }
    func suspend() {
        guard phase == .editing, let window, let canvas, let toolbar else { return }
        canvas.commitText()
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        NotificationCenter.default.removeObserver(self)
        NSColorPanel.shared.orderOut(nil)
        toolbar.orderOut()
        window.orderOut(nil)
        destroySavedEdit()
        lastEdit = SavedEdit(window: window, canvas: canvas, toolbar: toolbar,
                             documents: documents, screens: screens, activeID: activeID,
                             clipboardSession: clipboardSession, quickSelectionActive: quickSelectionActive)
        self.window = nil; self.canvas = nil; self.toolbar = nil
        documents.removeAll(); screens.removeAll(); activeID = nil
        phase = .idle; clipboardSession = false; quickSelectionActive = false
        AppDelegate.shared?.refreshMenu()
    }
    func resumeLastEdit() {
        guard let saved = lastEdit else { return }
        destroyActiveEdit()
        lastEdit = nil
        window = saved.window; canvas = saved.canvas; toolbar = saved.toolbar
        documents = saved.documents; screens = saved.screens; activeID = saved.activeID
        clipboardSession = saved.clipboardSession; quickSelectionActive = saved.quickSelectionActive
        phase = .editing
        installMonitor()
        if !clipboardSession {
            startTracking()
            NotificationCenter.default.addObserver(self, selector: #selector(cancel),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        saved.window.makeKeyAndOrderFront(nil)
        if let screen = saved.window.screen { saved.toolbar.show(screen: screen, parent: saved.window) }
        saved.window.makeFirstResponder(saved.canvas)
        AppDelegate.shared?.refreshMenu()
    }
    func discardLastEdit() {
        destroySavedEdit()
        AppDelegate.shared?.refreshMenu()
    }
    func activateUtility(_ tool: EditorTool) -> Bool {
        guard phase == .editing, let canvas else { return false }
        canvas.choose(tool)
        window?.makeKeyAndOrderFront(nil)
        return true
    }
    @objc func cancel() {
        destroyActiveEdit()
        AppDelegate.shared?.refreshMenu()
    }
    private func destroyActiveEdit() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        NotificationCenter.default.removeObserver(self)
        NSColorPanel.shared.orderOut(nil)
        toolbar?.close(); toolbar = nil
        window?.delegate = nil
        window?.close(); window = nil; canvas = nil
        documents.removeAll(); screens.removeAll(); activeID = nil
        phase = .idle; clipboardSession = false; quickSelectionActive = false
    }
    private func destroySavedEdit() {
        guard let saved = lastEdit else { return }
        saved.toolbar.close()
        saved.window.delegate = nil
        saved.window.close()
        lastEdit = nil
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let canvas else { return false }
        if let eventWindow = event.window, eventWindow != window, toolbar?.owns(eventWindow) != true { return false }
        // Native text fields retain typing, selection, and their own undo stack.
        if event.keyCode == 53 {
            requestCancel(); return true
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.command) {
                canvas.commitText(); finish(); return true
            }
            if event.modifierFlags.contains(.control) {
                canvas.commitText(); return true
            }
        }
        if canvas.isTyping { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            if key == "z" {
                canvas.history(redo: event.modifierFlags.contains(.shift)); return true
            }
            if key == "d" { canvas.duplicate(); return true }
            return false
        }
        guard event.modifierFlags.intersection([.option, .control]).isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if canvas.pendingCrop != nil { canvas.applyCrop() }
            return true
        }
        if event.keyCode == 48 { toolbar?.toggleVisible(); return true }
        if event.keyCode == 51 || event.keyCode == 117 { canvas.deleteSelected(); return true }
        if (123...126).contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGPoint
            switch event.keyCode {
            case 123: delta = CGPoint(x: -step, y: 0)
            case 124: delta = CGPoint(x: step, y: 0)
            case 125: delta = CGPoint(x: 0, y: -step)
            default: delta = CGPoint(x: 0, y: step)
            }
            canvas.nudge(delta); return true
        }
        if let tool = EditorTool.key(key) { canvas.choose(tool); return true }
        return false
    }
}

final class EditorCanvas: NSView, NSTextViewDelegate {
    let document: EditorDocument
    var tool = EditorTool.crop
    var style = EditorStyle.load(.crop)
    var onChange: (() -> Void)?
    var onInteraction: (() -> Void)?
    var onOCR: ((CGRect) -> Void)?
    var onMenu: (() -> NSMenu?)?
    var onQuickCrop: (() -> Void)?
    var onToolChosen: (() -> Void)?
    var onColorPicked: ((String, NSColor) -> Void)?
    var quickCropOnRelease = false
    private var message = ""
    private var messageToken = UUID()
    private var pickerPoint: CGPoint?
    private var sampler: NSBitmapImageRep?
    private var samplingTool = EditorTool.arrow
    func showMessage(_ text: String) {
        message = text; messageToken = UUID()
        let token = messageToken
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.messageToken == token else { return }
            self.message = ""; self.needsDisplay = true
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                                      owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        guard tool == .picker else { return }
        pickerPoint = point(event); needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { pickerPoint = nil; needsDisplay = true }
    func setPickerPoint(_ point: CGPoint) { pickerPoint = point; needsDisplay = true }
    func sampledColor(_ point: CGPoint) -> NSColor? {
        guard let sampler else { return nil }
        let x = min(sampler.pixelsWide - 1, max(0, Int(point.x / document.size.width * CGFloat(sampler.pixelsWide))))
        let y = min(sampler.pixelsHigh - 1, max(0, Int((document.size.height - point.y) / document.size.height * CGFloat(sampler.pixelsHigh))))
        return sampler.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }
    var pendingCrop: CGRect?
    private var selected: UUID?
    private var dragStart: CGPoint?
    private var draft: Annotation?
    private var original: Annotation?
    private var resizing = false
    private var cropMoveOrigin: CGRect?
    private var bitmap: CGImage?
    private var textView: NSTextView?
    private var textOrigin = CGPoint.zero
    private var editingTextID: UUID?
    var isTyping: Bool { NSApp.keyWindow?.firstResponder is NSTextView }
    var isDragging: Bool { dragStart != nil }
    var isInteracting: Bool { dragStart != nil || textView != nil || isTyping || pendingCrop != nil }
    override var acceptsFirstResponder: Bool { true }
    init(document: EditorDocument) {
        self.document = document
        bitmap = document.state.annotations.isEmpty ? document.image : document.render()
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel("Image editor. A arrow, R rectangle, E ellipse, T text, B blur, C crop, I color picker, O text recognition. Command Enter exports. Escape hides and preserves.")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : tool == .text ? .iBeam : .crosshair)
    }
    func choose(_ next: EditorTool, userInitiated: Bool = true) {
        onInteraction?()
        if userInitiated { onToolChosen?() }
        commitText(); dragStart = nil; draft = nil; original = nil; cropMoveOrigin = nil
        if next == .picker {
            samplingTool = tool == .picker ? samplingTool : tool
            if let image = document.render() { sampler = NSBitmapImageRep(cgImage: image) }
        } else { sampler = nil; pickerPoint = nil }
        tool = next; selected = nil; pendingCrop = nil
        style = EditorStyle.load(next)
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        changed()
    }
    func changeStyle(_ next: EditorStyle) {
        style = next
        let selectedItem = document.state.annotations.first(where: { $0.id == selected })
        next.save(selectedItem?.tool ?? tool)
        if let id = selected {
            var state = document.state
            if let i = state.annotations.firstIndex(where: { $0.id == id }) {
                state.annotations[i].style = next
                document.commit(state); rebuild()
            }
        }
        if let textView { textView.font = .systemFont(ofSize: next.fontSize, weight: .semibold); textView.textColor = next.color.ns }
        changed()
    }
    var selectedTool: EditorTool { document.state.annotations.first(where: { $0.id == selected })?.tool ?? tool }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let r = tool == .crop ? document.fullRect : document.cropRect
        return CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }
    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        commitText()
        window?.makeFirstResponder(self)
        let p = point(event)
        if tool == .picker {
            if let color = sampledColor(p) {
                let hex = EditorColor(color).hex
                if let onColorPicked { onColorPicked(hex, color); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                choose(samplingTool, userInitiated: false)
                var next = style
                if event.modifierFlags.contains(.option) { next.fill = EditorColor(color) }
                else { next.color = EditorColor(color) }
                changeStyle(next); showMessage(hex + " copied · color applied")
            }
            return
        }
        if tool == .text { beginText(at: p); return }
        if tool == .crop, event.clickCount == 2, pendingCrop?.contains(p) == true { applyCrop(); return }
        dragStart = p
        if tool == .crop, let crop = pendingCrop {
            let corners = [CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.maxY),
                           CGPoint(x: crop.minX, y: crop.maxY), CGPoint(x: crop.maxX, y: crop.minY)]
            if let corner = corners.first(where: { hypot(p.x - $0.x, p.y - $0.y) < 12 }) {
                let opposite = CGPoint(x: crop.minX + crop.maxX - corner.x, y: crop.minY + crop.maxY - corner.y)
                dragStart = opposite
                draft = Annotation(tool: .crop, start: opposite, end: p, style: style)
                pendingCrop = nil; changed(); return
            }
            if crop.contains(p) {
                cropMoveOrigin = crop
                draft = Annotation(tool: .crop, start: crop.origin, end: CGPoint(x: crop.maxX, y: crop.maxY), style: style)
                changed(); return
            }
        }
        if tool == .select {
            if let a = document.state.annotations.first(where: { $0.id == selected }),
               hypot(p.x - a.end.x, p.y - a.end.y) < 12 {
                original = a; draft = a; resizing = true
            } else {
                let hit = document.state.annotations.reversed().first { hitTest($0, point: p) }
                selected = hit?.id; original = hit; draft = hit; resizing = false
                if let hit { style = hit.style
                    if event.clickCount == 2 && hit.tool == .text {
                        dragStart = nil; draft = nil; original = nil
                        beginText(at: hit.rect.origin, existing: hit); return
                    }
                }
            }
            if let selected { bitmap = document.render(excluding: selected) }
        } else {
            selected = nil
            draft = Annotation(tool: tool, start: p, end: p, style: style)
        }
        changed()
    }
    private func hitTest(_ a: Annotation, point p: CGPoint) -> Bool {
        if a.tool == .arrow || a.tool == .line {
            let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
            let t = min(1, max(0, ((p.x - a.start.x) * dx + (p.y - a.start.y) * dy) / max(1, dx * dx + dy * dy)))
            return hypot(p.x - a.start.x - t * dx, p.y - a.start.y - t * dy) <= max(8, a.style.width)
        }
        return a.rect.insetBy(dx: -5, dy: -5).contains(p)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var p = point(event)
        if tool == .crop, let crop = cropMoveOrigin {
            let boundary = document.fullRect
            let x = min(max(crop.minX + p.x - start.x, boundary.minX), boundary.maxX - crop.width)
            let y = min(max(crop.minY + p.y - start.y, boundary.minY), boundary.maxY - crop.height)
            draft?.start = CGPoint(x: x, y: y)
            draft?.end = CGPoint(x: x + crop.width, y: y + crop.height)
        } else if tool == .select, var a = original {
            if resizing { a.end = p }
            else { a.move(CGPoint(x: p.x - start.x, y: p.y - start.y)) }
            draft = a
        } else {
            if event.modifierFlags.contains(.shift) {
                let dx = p.x - start.x, dy = p.y - start.y
                if tool == .arrow || tool == .line {
                    let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                    let distance = hypot(dx, dy)
                    p = CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance)
                } else {
                    let length = min(abs(dx), abs(dy))
                    p = CGPoint(x: start.x + (dx < 0 ? -length : length), y: start.y + (dy < 0 ? -length : length))
                }
            }
            draft?.end = p
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        defer { dragStart = nil; draft = nil; original = nil; cropMoveOrigin = nil; changed() }
        guard let a = draft else { return }
        if tool == .crop {
            if a.rect.width >= 2 && a.rect.height >= 2 {
                pendingCrop = a.rect.intersection(document.fullRect)
                if quickCropOnRelease {
                    applyCrop()
                    DispatchQueue.main.async { [weak self] in self?.onQuickCrop?() }
                }
            }
            return
        }
        if tool == .ocr { if a.rect.width >= 2 && a.rect.height >= 2 { onOCR?(a.rect) }; return }
        var state = document.state
        if tool == .select {
            if let i = state.annotations.firstIndex(where: { $0.id == a.id }) { state.annotations[i] = a }
        } else if hypot(a.end.x - a.start.x, a.end.y - a.start.y) >= 3 {
            state.annotations.append(a)
        }
        document.commit(state); rebuild()
    }
    func applyCrop() {
        guard let rect = pendingCrop else { return }
        var state = document.state; state.crop = rect.intersection(document.fullRect)
        document.commit(state); pendingCrop = nil; selected = nil; changed()
    }
    func cancelPending() -> Bool {
        if textView != nil { textView?.removeFromSuperview(); textView = nil; editingTextID = nil; rebuild(); window?.makeFirstResponder(self); return true }
        if dragStart != nil || pendingCrop != nil {
            dragStart = nil; draft = nil; original = nil; cropMoveOrigin = nil; pendingCrop = nil; rebuild(); changed(); return true
        }
        return false
    }
    func history(redo: Bool) {
        commitText(); pendingCrop = nil; draft = nil; original = nil; dragStart = nil; cropMoveOrigin = nil
        if redo { document.redo() } else { document.undo() }
        selected = nil; rebuild(); changed()
    }
    func deleteSelected() {
        guard let selected else { return }
        var state = document.state; state.annotations.removeAll { $0.id == selected }
        document.commit(state); self.selected = nil; rebuild(); changed()
    }
    func duplicate() {
        guard var a = document.state.annotations.first(where: { $0.id == selected }) else { return }
        a.id = UUID(); a.move(CGPoint(x: 12, y: -12))
        var state = document.state; state.annotations.append(a); document.commit(state)
        selected = a.id; rebuild(); changed()
    }
    func nudge(_ delta: CGPoint) {
        guard let id = selected else { return }
        var state = document.state
        if let i = state.annotations.firstIndex(where: { $0.id == id }) {
            state.annotations[i].move(delta); document.commit(state); rebuild(); changed()
        }
    }
    private func beginText(at p: CGPoint, existing: Annotation? = nil) {
        textOrigin = p; editingTextID = existing?.id
        if let existing { style = existing.style }
        let width = min(420, max(100, bounds.maxX - p.x))
        let height = min(180, max(50, p.y))
        let rect = existing?.rect ?? CGRect(x: p.x, y: max(0, p.y - height), width: width, height: height)
        let editor = NSTextView(frame: rect)
        editor.font = .systemFont(ofSize: style.fontSize, weight: .semibold)
        editor.textColor = style.color.ns
        editor.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        editor.insertionPointColor = .white
        editor.isRichText = false; editor.allowsUndo = true
        editor.textContainerInset = CGSize(width: 8, height: 6)
        editor.string = existing?.text ?? ""
        editor.delegate = self
        textOrigin = rect.origin
        textView = editor; addSubview(editor)
        if let existing { bitmap = document.render(excluding: existing.id) }
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        changed()
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            commitText()
            return true
        }
        return false
    }
    func commitText() {
        guard let editor = textView else { return }
        let text = editor.string
        textView = nil; editor.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { editingTextID = nil; rebuild(); return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)]
        let measured = (text as NSString).boundingRect(with: CGSize(width: editor.frame.width - 16, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        let height = min(document.size.height, ceil(measured.height) + 16)
        let rect = CGRect(x: editor.frame.minX, y: max(0, editor.frame.maxY - height),
                          width: min(editor.frame.width, max(40, ceil(measured.width) + 20)), height: height)
        var a = Annotation(tool: .text, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), style: style, text: text)
        var state = document.state
        if let id = editingTextID, let i = state.annotations.firstIndex(where: { $0.id == id }) {
            a.id = id; state.annotations[i] = a
        } else { state.annotations.append(a) }
        editingTextID = nil
        document.commit(state); rebuild(); changed()
    }
    private func rebuild() { bitmap = document.render() }
    private func changed() { needsDisplay = true; onChange?() }
    override func draw(_ dirtyRect: NSRect) {
        if let bitmap { NSImage(cgImage: bitmap, size: document.size).draw(in: bounds) }
        if let draft, tool != .crop && tool != .select {
            if tool == .blur || tool == .ocr {
                NSColor.white.setStroke(); NSBezierPath(rect: draft.rect).stroke()
            } else { EditorDocument.draw(draft) }
        }
        if tool == .select, let draft, original != nil {
            // Render the vector move preview without creating an undo entry.
            EditorDocument.draw(draft)
        }
        let crop = tool == .crop && dragStart != nil ? draft?.rect : pendingCrop ?? document.state.crop
        if let crop {
            let shade = NSBezierPath(rect: bounds); shade.appendRect(crop)
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(pendingCrop == nil && dragStart == nil ? 0.94 : 0.55).setFill(); shade.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: crop); border.lineWidth = 1; border.stroke()
            let sx = CGFloat(document.image.width) / document.size.width
            let sy = CGFloat(document.image.height) / document.size.height
            let caption = "\(Int((crop.width * sx).rounded())) × \(Int((crop.height * sy).rounded())) px" + (pendingCrop != nil || dragStart != nil ? " · Enter to apply crop" : " · Cropped")
            (caption as NSString).draw(at: CGPoint(x: crop.minX + 5, y: max(8, crop.minY - 24)),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
                                 .backgroundColor: NSColor.black])
            if pendingCrop != nil {
                for x in [crop.minX, crop.maxX] {
                    for y in [crop.minY, crop.maxY] {
                        NSColor.white.setFill()
                        NSBezierPath(rect: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)).fill()
                    }
                }
            }
        }
        if let a = draft ?? document.state.annotations.first(where: { $0.id == selected }), tool == .select {
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: a.rect.insetBy(dx: -5, dy: -5)).stroke()
            NSColor.white.setFill()
            NSBezierPath(rect: CGRect(x: a.end.x - 5, y: a.end.y - 5, width: 10, height: 10)).fill()
        }
        if tool == .picker, let p = pickerPoint, let color = sampledColor(p), let sampler {
            let zoom = enclosingScrollView?.magnification ?? 1
            let visible = visibleRect.intersection(bounds)
            let side: CGFloat = min(180 / zoom, max(26 / zoom, min(visible.width, visible.height - 30 / zoom)))
            let cell = side / 13
            let x = min(max(p.x + 24 / zoom, visible.minX), max(visible.minX, visible.maxX - side))
            let y = min(max(p.y + 24 / zoom, visible.minY + 30 / zoom), max(visible.minY, visible.maxY - side))
            let lens = CGRect(x: x, y: y, width: side, height: side)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: lens).addClip()
            let px = Int(p.x / document.size.width * CGFloat(sampler.pixelsWide))
            let py = Int((document.size.height - p.y) / document.size.height * CGFloat(sampler.pixelsHigh))
            for row in -6...6 { for col in -6...6 {
                let cx = min(sampler.pixelsWide - 1, max(0, px + col))
                let cy = min(sampler.pixelsHigh - 1, max(0, py + row))
                (sampler.colorAt(x: cx, y: cy) ?? .black).setFill()
                let box = CGRect(x: x + CGFloat(col + 6) * cell, y: y + CGFloat(6 - row) * cell, width: cell, height: cell)
                box.fill(); NSColor.gray.withAlphaComponent(0.5).setStroke(); NSBezierPath(rect: box).stroke()
            }}
            let center = NSBezierPath(rect: CGRect(x: x + 6 * cell, y: y + 6 * cell, width: cell, height: cell))
            NSColor.black.setStroke(); center.lineWidth = 3 / zoom; center.stroke()
            NSColor.white.setStroke(); center.lineWidth = 1 / zoom; center.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let rim = NSBezierPath(ovalIn: lens)
            NSColor.black.setStroke(); rim.lineWidth = 3 / zoom; rim.stroke()
            NSColor.white.setStroke(); rim.lineWidth = 1 / zoom; rim.stroke()
            (EditorColor(color).hex as NSString).draw(at: CGPoint(x: x + 40 / zoom, y: y - 24 / zoom),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16 / zoom, weight: .bold),
                                 .foregroundColor: NSColor.white, .backgroundColor: NSColor.black])
        }
        if !message.isEmpty {
            let zoom = enclosingScrollView?.magnification ?? 1
            (message as NSString).draw(at: CGPoint(x: visibleRect.minX + 20 / zoom, y: visibleRect.minY + 24 / zoom),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15 / zoom, weight: .medium),
                                 .foregroundColor: NSColor.white, .backgroundColor: NSColor.black])
        }
    }
}

final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension EditorColor {
    var hex: String {
        [r, g, b].map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                          green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1))
    }
}

enum EditorOCR {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let sorted = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        // Vision can split a printed line into several observations. Group those
        // fragments into rows before ordering horizontally, without flattening lines.
        var rows: [[VNRecognizedTextObservation]] = []
        for item in sorted {
            if let index = rows.indices.last, let first = rows[index].first,
               abs(first.boundingBox.midY - item.boundingBox.midY) < min(first.boundingBox.height, item.boundingBox.height) * 0.4 {
                rows[index].append(item)
            } else { rows.append([item]) }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

final class GlobalUtilitySession {
    static let shared = GlobalUtilitySession()
    enum Mode { case picker, ocr }
    private(set) var isActive = false
    private var token = UUID()
    private var window: EditorWindow?
    private var monitor: Any?

    func begin(_ mode: Mode) {
        if EditorSession.shared.activateUtility(mode == .picker ? .picker : .ocr) { return }
        guard !isActive else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            AppDelegate.shared?.showErrorMessage("No display is available under the pointer."); return
        }
        isActive = true; token = UUID()
        let requestToken = token
        let id = number.uint32Value
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw NSError(domain: "ShotKey", code: 10, userInfo: [NSLocalizedDescriptionKey: "The display under the pointer is unavailable."])
                }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = CGDisplayPixelsWide(id); config.height = CGDisplayPixelsHigh(id)
                config.showsCursor = false; config.capturesAudio = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard self.token == requestToken, self.isActive else { return }
                self.show(image: image, screen: screen, mode: mode)
            } catch {
                guard self.token == requestToken else { return }
                self.cancel()
                if !CGPreflightScreenCaptureAccess() {
                    _ = CGRequestScreenCaptureAccess()
                    AppDelegate.shared?.showErrorMessage("Screen Recording permission is required. Quit and reopen ShotKey after granting access.")
                } else { AppDelegate.shared?.showError(error) }
            }
        }
    }
    private func show(image: CGImage, screen: NSScreen, mode: Mode) {
        let document = EditorDocument(image: image, size: screen.frame.size)
        let canvas = EditorCanvas(document: document)
        canvas.frame = CGRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]
        let win = EditorWindow(contentRect: canvas.frame, styleMask: .borderless,
            backing: .buffered, defer: false, screen: screen)
        win.setFrame(screen.frame, display: true); win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false; win.contentView = canvas
        window = win
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
        }
        NSApp.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil); win.makeFirstResponder(canvas)
        if mode == .picker {
            canvas.choose(.picker, userInitiated: false)
            let global = NSEvent.mouseLocation
            canvas.setPickerPoint(CGPoint(x: global.x - screen.frame.minX, y: global.y - screen.frame.minY))
            canvas.onColorPicked = { [weak self] hex, color in
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                self?.cancel()
                AppDelegate.shared?.showColorCopied(hex, color: color, screen: screen)
            }
        } else {
            canvas.choose(.ocr, userInitiated: false)
            canvas.showMessage("Drag around text · Escape cancels")
            canvas.onOCR = { [weak self, weak canvas] rect in
                guard let self, let canvas, let rendered = canvas.document.render() else { return }
                let sx = CGFloat(rendered.width) / canvas.document.size.width
                let sy = CGFloat(rendered.height) / canvas.document.size.height
                let pixels = CGRect(x: rect.minX * sx, y: (canvas.document.size.height - rect.maxY) * sy,
                                    width: rect.width * sx, height: rect.height * sy).integral
                guard let selected = rendered.cropping(to: pixels) else { return }
                let requestToken = self.token
                self.cancel(keepToken: true)
                AppDelegate.shared?.showUtilityMessage("Reading text…", screen: screen)
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try EditorOCR.recognize(selected) }
                    DispatchQueue.main.async {
                        guard self.token == requestToken else { return }
                        switch result {
                        case .success(let text) where !text.isEmpty:
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                            AppDelegate.shared?.showUtilityMessage("✓ Text copied · line breaks preserved", screen: screen)
                        case .success: AppDelegate.shared?.showUtilityMessage("No text found", screen: screen)
                        case .failure(let error): AppDelegate.shared?.showError(error)
                        }
                    }
                }
            }
        }
    }
    func cancel(keepToken: Bool = false) {
        if !keepToken { token = UUID() }
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        window?.orderOut(nil); window?.close(); window = nil
        isActive = false
    }
}

final class EditorToolbar: NSObject, NSTextFieldDelegate {
    private let panel: NSPanel
    private weak var canvas: EditorCanvas?
    private weak var session: EditorSession?
    private let row = NSStackView()
    private var buttons: [NSButton] = []
    private let color = NSColorWell()
    private let fill = NSColorWell()
    private let hex = NSTextField(string: "FF0000")
    private let fillHex = NSTextField(string: "000000")
    private let width = NSTextField(string: "3")
    private let font = NSTextField(string: "28")
    private let blur = NSTextField(string: "14")
    private let mode = NSPopUpButton()
    private let background = NSButton(checkboxWithTitle: "BG", target: nil, action: nil)
    private let restore = NSButton()
    private var options: [NSView] = []
    init(canvas: EditorCanvas, session: EditorSession) {
        self.canvas = canvas; self.session = session
        panel = EditorPanel(contentRect: CGRect(x: 0, y: 0, width: 900, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true; panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        row.orientation = .horizontal; row.spacing = 3; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = row
        let symbols = ["cursorarrow", "arrow.up.right", "line.diagonal", "rectangle", "circle", "textformat", "drop.halffull", "crop", "eyedropper", "text.viewfinder"]
        for (i, tool) in EditorTool.allCases.enumerated() {
            let button = NSButton(image: NSImage(systemSymbolName: symbols[i], accessibilityDescription: tool.label) ?? NSImage(),
                                  target: self, action: #selector(selectTool(_:)))
            button.tag = i; button.toolTip = tool.label; button.bezelStyle = .rounded
            button.setButtonType(.toggle); button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            buttons.append(button); row.addArrangedSubview(button)
        }
        mode.addItems(withTitles: ["Stroke", "Fill", "Both"])
        for control in [mode as NSControl, background, color, fill] {
            control.target = self; control.action = #selector(styleChanged)
        }
        for well in [color, fill] {
            well.widthAnchor.constraint(equalToConstant: 30).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        color.toolTip = "Stroke / text color"; fill.toolTip = "Shape fill / text background color"
        for field in [hex, fillHex, width, font, blur] {
            field.delegate = self; field.target = self; field.action = #selector(commitField)
            field.widthAnchor.constraint(equalToConstant: field == hex || field == fillHex ? 64 : 40).isActive = true
            field.alignment = .center
        }
        hex.toolTip = "Color: six hexadecimal digits, no #"
        fillHex.toolTip = "Background / fill: six hexadecimal digits, no #"
        width.toolTip = "Stroke width"; font.toolTip = "Text size"; blur.toolTip = "Blur strength"
        let more = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Editor actions")!,
                            target: self, action: #selector(showMenu(_:)))
        more.translatesAutoresizingMaskIntoConstraints = false; more.bezelStyle = .rounded
        let save = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Export image")!,
                            target: self, action: #selector(finish))
        save.translatesAutoresizingMaskIntoConstraints = false; save.bezelStyle = .rounded
        save.toolTip = "Export image (Command–Enter)"
        restore.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: "Restore last edit")
        restore.target = self; restore.action = #selector(restoreLastEdit)
        restore.translatesAutoresizingMaskIntoConstraints = false; restore.bezelStyle = .rounded
        restore.toolTip = "Restore last preserved edit"
        let root = panel.contentView!
        root.addSubview(scroll); root.addSubview(restore); root.addSubview(save); root.addSubview(more)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
            scroll.trailingAnchor.constraint(equalTo: restore.leadingAnchor, constant: -3),
            restore.widthAnchor.constraint(equalToConstant: 32),
            restore.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            restore.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -3),
            save.widthAnchor.constraint(equalToConstant: 32),
            save.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -3),
            more.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            more.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: 32),
            row.heightAnchor.constraint(equalToConstant: 32)
        ])
        refresh()
    }
    func show(screen: NSScreen, parent: NSWindow) {
        let available = parent.styleMask.contains(.titled) ? parent.frame : screen.visibleFrame
        panel.setContentSize(CGSize(width: min(900, available.width - 20), height: 44))
        panel.setFrameOrigin(CGPoint(x: available.midX - panel.frame.width / 2, y: available.maxY - (parent.styleMask.contains(.titled) ? 76 : 52)))
        #if !EDITOR_TESTS
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.hidesOnDeactivate = parent.styleMask.contains(.titled)
        panel.orderFrontRegardless()
        #endif
        refresh()
    }
    func owns(_ window: NSWindow) -> Bool { panel == window }
    func close() { panel.parent?.removeChildWindow(panel); panel.close() }
    func orderOut() { panel.orderOut(nil) }
    func toggleVisible() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    func refresh() {
        guard let canvas else { return }
        restore.isEnabled = session?.hasLastEdit == true
        let s = canvas.style, tool = canvas.selectedTool
        for (i, button) in buttons.enumerated() { button.state = EditorTool.allCases[i] == canvas.tool ? .on : .off }
        color.color = s.color.ns; fill.color = s.fill.ns
        hex.stringValue = s.color.hex; fillHex.stringValue = s.fill.hex
        width.doubleValue = s.width; font.doubleValue = s.fontSize; blur.doubleValue = s.blur
        mode.selectItem(at: s.fillMode); background.state = s.textBackground ? .on : .off
        var nextOptions: [NSView] = []
        switch tool {
        case .arrow, .line: nextOptions = [color, hex, width]
        case .rectangle, .ellipse: nextOptions = [color, hex, width, mode, fill, fillHex]
        case .text: nextOptions = [color, hex, font, background, fill, fillHex]
        case .blur: nextOptions = [blur]
        default: break
        }
        if options != nextOptions {
            options.forEach { row.removeArrangedSubview($0); $0.removeFromSuperview() }
            options = nextOptions
            options.forEach { row.addArrangedSubview($0) }
        }
        row.layoutSubtreeIfNeeded()
        if let parent = panel.parent {
            let maxWidth = max(300, min(parent.frame.width - 20, parent.screen?.visibleFrame.width ?? 900))
            let target = min(maxWidth, row.fittingSize.width + 126)
            panel.setFrame(CGRect(x: parent.frame.midX - target / 2, y: panel.frame.minY, width: target, height: 44), display: true)
        }
    }
    func actionMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = enabled; menu.addItem(item)
        }
        menu.autoenablesItems = false
        add("Export image · ⌘↩", #selector(finish))
        add("Apply crop · Enter", #selector(crop), enabled: canvas?.pendingCrop != nil)
        add("Undo · ⌘Z", #selector(undo), enabled: canvas?.document.undoStates.isEmpty == false)
        add("Redo · ⇧⌘Z", #selector(redo), enabled: canvas?.document.redoStates.isEmpty == false)
        add("Copy all visible text (OCR)", #selector(ocr))
        menu.addItem(.separator())
        for (index, mode) in [OutputMode.both, .clipboardOnly, .fileOnly].enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(setOutput(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.state = session?.outputMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Hide and preserve edit · Esc", #selector(cancel))
        add("Discard edit permanently", #selector(discard))
        return menu
    }
    @objc private func showMenu(_ sender: NSButton) { actionMenu().popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.minY), in: sender) }
    @objc private func restoreLastEdit() { session?.resumeLastEdit() }
    @objc private func setOutput(_ sender: NSMenuItem) {
        session?.outputMode = [OutputMode.both, .clipboardOnly, .fileOnly][sender.tag]
        canvas?.showMessage("Output: " + (session?.outputMode.title ?? ""))
    }
    @objc private func selectTool(_ sender: NSButton) { canvas?.choose(EditorTool.allCases[sender.tag]) }
    @objc private func commitField() {
        guard EditorColor(hex: hex.stringValue) != nil, EditorColor(hex: fillHex.stringValue) != nil else {
            canvas?.showMessage("Use exactly six hexadecimal digits, such as 5785D1"); refresh(); return
        }
        color.color = EditorColor(hex: hex.stringValue)!.ns; fill.color = EditorColor(hex: fillHex.stringValue)!.ns
        styleChanged(); canvas?.window?.makeFirstResponder(canvas)
    }
    @objc private func styleChanged() {
        guard let canvas else { return }
        var s = canvas.style
        s.color = EditorColor(color.color); s.fill = EditorColor(fill.color)
        s.width = min(40, max(1, width.doubleValue)); s.fontSize = min(240, max(8, font.doubleValue))
        s.blur = min(100, max(1, blur.doubleValue))
        s.fillMode = max(0, mode.indexOfSelectedItem); s.textBackground = background.state == .on
        s.textOutline = 0
        canvas.changeStyle(s)
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitField() }
    @objc private func undo() { canvas?.history(redo: false) }
    @objc private func redo() { canvas?.history(redo: true) }
    @objc private func crop() { canvas?.applyCrop() }
    @objc private func ocr() { canvas?.commitText(); session?.recognize() }
    @objc private func finish() { panel.makeFirstResponder(nil); session?.finish() }
    @objc private func cancel() { session?.requestCancel() }
    @objc private func discard() { session?.cancel() }
    #if EDITOR_TESTS
    func presentPreview(_ parent: NSWindow) {
        parent.addChildWindow(panel, ordered: .above)
        show(screen: parent.screen ?? NSScreen.main!, parent: parent)
        panel.orderFrontRegardless()
    }
    func writePreview(_ url: URL) throws {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    #endif
}
