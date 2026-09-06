import AppKit
import ScreenCaptureKit
import CoreImage

enum EditorTool: String, CaseIterable, Codable {
    case select, arrow, line, rectangle, ellipse, text, blur, crop
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
        }
    }
    static func key(_ key: String) -> EditorTool? {
        ["v": .select, "a": .arrow, "l": .line, "r": .rectangle,
         "e": .ellipse, "t": .text, "b": .blur, "c": .crop][key]
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
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: s.color.ns, .paragraphStyle: paragraph
            ]
            if s.textOutline > 0 {
                attributes[.strokeWidth] = -s.textOutline
                attributes[.strokeColor] = s.outline.ns
            }
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
final class EditorSession: NSObject {
    static let shared = EditorSession()
    enum Phase { case idle, loading, editing, finishing }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
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
        return try await withThrowingTaskGroup(of: (CGDirectDisplayID, CGImage).self) { group in
            for (id, _) in candidates {
                guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = CGDisplayPixelsWide(id)
                    config.height = CGDisplayPixelsHigh(id)
                    config.showsCursor = false; config.capturesAudio = false
                    return (id, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
                }
            }
            var results: [CGDirectDisplayID: CGImage] = [:]
            for try await (id, image) in group { results[id] = image }
            return results
        }
    }

    func toggle() {
        switch phase {
        case .loading, .finishing: return
        case .editing:
            if canvas?.isDragging != true { finish() }
        case .idle: begin()
        }
    }
    private func begin() {
        phase = .loading
        generation = UUID()
        let token = generation
        // Escape works even if capture is still awaiting the system.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.phase == .loading && event.keyCode == 53 { self.cancel(); return nil }
            if self.phase == .editing { return self.handleKey(event) ? nil : event }
            return event
        }
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
        newCanvas.choose(previousTool)
        let newToolbar = EditorToolbar(canvas: newCanvas, session: self)
        toolbar = newToolbar
        newCanvas.onChange = { [weak newToolbar] in newToolbar?.refresh() }
        newToolbar.show(screen: screen, parent: newWindow)
    }
    func finish() {
        guard phase == .editing, let canvas else { return }
        canvas.commitText()
        canvas.applyCrop()
        phase = .finishing
        guard let result = canvas.document.render(cropped: true) else {
            phase = .editing
            AppDelegate.shared?.showErrorMessage("The edited image could not be rendered. Your edits are still open.")
            return
        }
        if CaptureService.shared.deliverOnMain(result) { cancel() }
        else { phase = .editing }
    }
    @objc func cancel() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        NotificationCenter.default.removeObserver(self)
        NSColorPanel.shared.orderOut(nil)
        toolbar?.close(); toolbar = nil
        window?.close(); window = nil; canvas = nil
        documents.removeAll(); screens.removeAll(); activeID = nil
        phase = .idle
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let canvas else { return false }
        // Native text fields retain typing, selection, and their own undo stack.
        if event.keyCode == 53 {
            if canvas.cancelPending() { return true }
            cancel(); return true
        }
        if canvas.isTyping { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            if key == "z" {
                canvas.history(redo: event.modifierFlags.contains(.shift)); return true
            }
            if key == "s" { finish(); return true }
            if key == "d" { canvas.duplicate(); return true }
            return false
        }
        guard event.modifierFlags.intersection([.option, .control]).isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if canvas.pendingCrop != nil { canvas.applyCrop() } else { finish() }
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
        setAccessibilityLabel("Frozen screenshot. A arrow, R rectangle, E ellipse, T text, B blur, C crop. Escape cancels.")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : tool == .text ? .iBeam : .crosshair)
    }
    func choose(_ next: EditorTool) {
        commitText(); dragStart = nil; draft = nil; original = nil; cropMoveOrigin = nil
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
        let r = document.cropRect
        return CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = point(event)
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
            let boundary = document.cropRect
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
            if a.rect.width >= 2 && a.rect.height >= 2 { pendingCrop = a.rect.intersection(document.cropRect) }
            return
        }
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
        var state = document.state; state.crop = rect.intersection(document.cropRect)
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
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
            commitText(); return true
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
            if tool == .blur {
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
            NSColor.black.withAlphaComponent(0.55).setFill(); shade.fill()
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
    }
}

final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class EditorToolbar: NSObject, NSTextFieldDelegate {
    private let panel: NSPanel
    private weak var canvas: EditorCanvas?
    private weak var session: EditorSession?
    private var toolButtons: [NSButton] = []
    private let color = NSColorWell()
    private let fill = NSColorWell()
    private let outlineColor = NSColorWell()
    private let width = NSTextField(string: "3")
    private let font = NSTextField(string: "28")
    private let blur = NSTextField(string: "14")
    private let textStroke = NSTextField(string: "0")
    private let mode = NSPopUpButton()
    private let background = NSButton(checkboxWithTitle: "Text background", target: nil, action: nil)
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let cropButton = NSButton()
    private let status = NSTextField(labelWithString: "")
    init(canvas: EditorCanvas, session: EditorSession) {
        self.canvas = canvas; self.session = session
        panel = EditorPanel(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 150),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true; panel.hasShadow = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let tools = NSStackView()
        tools.orientation = .horizontal; tools.spacing = 4
        for (i, tool) in EditorTool.allCases.enumerated() {
            let button = NSButton(title: tool.label, target: self, action: #selector(selectTool(_:)))
            button.tag = i; button.bezelStyle = .rounded; button.setButtonType(.toggle)
            toolButtons.append(button); tools.addArrangedSubview(button)
        }
        configure(undoButton, "Undo ⌘Z", #selector(undo))
        configure(redoButton, "Redo ⇧⌘Z", #selector(redo))
        configure(cropButton, "✓ Crop", #selector(crop))
        let done = NSButton(title: "Done " + Preferences.shared.regionShortcut.readable, target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel Esc", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        let actions = NSStackView(views: [undoButton, redoButton, cropButton, done, cancel])
        actions.spacing = 6
        let top = tools
        mode.addItems(withTitles: ["Outline", "Fill", "Outline + fill"])
        mode.target = self; mode.action = #selector(styleChanged)
        background.target = self; background.action = #selector(styleChanged)
        for well in [color, fill, outlineColor] {
            well.target = self; well.action = #selector(styleChanged)
            well.widthAnchor.constraint(equalToConstant: 38).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        for field in [width, font, blur, textStroke] {
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 45).isActive = true
            field.alignment = .center
            field.target = self; field.action = #selector(styleChanged)
        }
        let options = NSStackView(views: [
            label("Color"), color, label("Fill"), fill, mode, label("Stroke"), width,
            label("Text size"), font, background, label("Text outline"), textStroke,
            outlineColor, label("Blur"), blur
        ])
        options.spacing = 7
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [top, options, actions, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 14),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.contentView!.trailingAnchor, constant: -14)
        ])
        refresh()
    }
    private func label(_ title: String) -> NSTextField { NSTextField(labelWithString: title) }
    private func configure(_ button: NSButton, _ title: String, _ action: Selector) {
        button.title = title; button.target = self; button.action = action; button.bezelStyle = .rounded
    }
    func show(screen: NSScreen, parent: NSWindow) {
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.maxY - 155))
        #if !EDITOR_TESTS
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        #endif
    }
    #if EDITOR_TESTS
    func presentPreview(_ parent: NSWindow) {
        parent.addChildWindow(panel, ordered: .above)
        panel.setFrameOrigin(CGPoint(x: parent.frame.minX, y: parent.frame.maxY - 165))
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
    func close() { panel.parent?.removeChildWindow(panel); panel.close() }
    func toggleVisible() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    func refresh() {
        guard let canvas else { return }
        let s = canvas.style, tool = canvas.selectedTool
        for (i, button) in toolButtons.enumerated() { button.state = EditorTool.allCases[i] == canvas.tool ? .on : .off }
        color.color = s.color.ns; fill.color = s.fill.ns; outlineColor.color = s.outline.ns
        width.doubleValue = s.width; font.doubleValue = s.fontSize
        blur.doubleValue = s.blur; textStroke.doubleValue = s.textOutline
        mode.selectItem(at: s.fillMode); background.state = s.textBackground ? .on : .off
        mode.isEnabled = [.rectangle, .ellipse].contains(tool)
        font.isEnabled = tool == .text; background.isEnabled = tool == .text
        textStroke.isEnabled = tool == .text; outlineColor.isEnabled = tool == .text
        blur.isEnabled = tool == .blur
        undoButton.isEnabled = !canvas.document.undoStates.isEmpty
        redoButton.isEnabled = !canvas.document.redoStates.isEmpty
        cropButton.isEnabled = canvas.pendingCrop != nil
        status.stringValue = "Frozen screen · Drag to crop, or choose a tool · Shift: circle / square / snapped line · V: move / resize · Text: Enter commits, Shift–Enter adds a line · Tab hides toolbar · " + Preferences.shared.outputMode.title
    }
    @objc private func selectTool(_ sender: NSButton) { canvas?.choose(EditorTool.allCases[sender.tag]) }
    @objc private func styleChanged() {
        guard let canvas else { return }
        var s = canvas.style
        s.color = EditorColor(color.color); s.fill = EditorColor(fill.color); s.outline = EditorColor(outlineColor.color)
        s.width = min(40, max(1, width.doubleValue))
        s.fontSize = min(240, max(8, font.doubleValue))
        s.blur = min(100, max(1, blur.doubleValue))
        s.textOutline = min(20, max(0, textStroke.doubleValue))
        s.fillMode = max(0, mode.indexOfSelectedItem); s.textBackground = background.state == .on
        canvas.changeStyle(s)
    }
    func controlTextDidEndEditing(_ obj: Notification) { styleChanged() }
    @objc private func undo() { canvas?.history(redo: false) }
    @objc private func redo() { canvas?.history(redo: true) }
    @objc private func crop() { canvas?.applyCrop() }
    @objc private func finish() { panel.makeFirstResponder(nil); session?.finish() }
    @objc private func cancel() { session?.cancel() }
}
