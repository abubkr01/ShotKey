import AppKit

// Lightweight runner for Macs with Command Line Tools but no XCTest framework.
class XCTestCase {}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "\(a) != \(b)", file: file, line: line) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a < b, "\(a) is not < \(b)", file: file, line: line) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a > b, "\(a) is not > \(b)", file: file, line: line) }
struct TestShortcut { var readable = "⌥1" }
enum OutputMode: String {
    case both, clipboardOnly, fileOnly
    var title: String { rawValue }
}
class Preferences {
    static let shared = Preferences()
    let regionShortcut = TestShortcut()
    var outputMode = OutputMode.both
    var clipboardOutputMode = OutputMode.clipboardOnly
    var quickSelectionOutputMode = OutputMode.both
}
class CaptureService {
    static let shared = CaptureService()
    var results: [CGImage] = []
    func deliver(_ image: CGImage) { results.append(image) }
    func deliverOnMain(_ image: CGImage, mode: OutputMode? = nil) -> Bool { results.append(image); return true }
}
class AppDelegate {
    static var shared: AppDelegate? = AppDelegate()
    func showError(_ error: Error) { print("Capture error: \(error)") }
    func showErrorMessage(_ message: String) { print(message) }
    func refreshMenu() {}
    func showColorCopied(_ hex: String, color: NSColor, screen: NSScreen?) {}
    func showUtilityMessage(_ message: String, screen: NSScreen?) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let tests = EditorTests()
tests.testFiveHundredUndoRedoAndBranchingHistory()
print("PASS 500 undo/redo operations and branching history")
tests.testRetinaCropDimensionsAndTopLeftOrientation()
print("PASS Retina crop pixels, orientation, undo and redo")
tests.testFilledRectangleAndEllipseDoNotChangeOutsidePixels()
print("PASS rectangle/ellipse rendering and unaffected pixels")
tests.testBlurAffectsOnlyRequestedRectangle()
print("PASS blur changes only the chosen region")
try tests.testStyleSerializationRetainsIndependentToolSettings()
print("PASS style round-trip and tool shortcuts")

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
}
let session = EditorSession()
var captures = 0
session.snapshotSource = { candidates in
    captures += 1
    try await Task.sleep(nanoseconds: 50_000_000)
    return Dictionary(uniqueKeysWithValues: candidates.map { ($0.0, tests.fixture()) })
}
session.toggle()
session.toggle()
session.toggle()
XCTAssertTrue(session.phase == .loading)
pump(0.2)
XCTAssertEqual(captures, 1)
XCTAssertTrue(session.phase == .editing)
session.toggle()
XCTAssertTrue(session.phase == .editing)
XCTAssertEqual(CaptureService.shared.results.count, 0)
session.finish()
XCTAssertTrue(session.phase == .idle)
XCTAssertEqual(CaptureService.shared.results.count, 1)
session.toggle()
session.cancel()
pump(0.2)
XCTAssertTrue(session.phase == .idle)
XCTAssertEqual(CaptureService.shared.results.count, 1)
print("PASS repeated hotkey cannot export, explicit finish exports once, cancelled capture cannot reopen")

let d = EditorDocument(image: tests.fixture(width: 1100, height: 700), size: CGSize(width: 1100, height: 700))
var state = d.state
var textStyle = EditorStyle(); textStyle.color = EditorColor(.white)
textStyle.textBackground = true; textStyle.fontSize = 28
state.annotations.append(Annotation(tool: .text, start: CGPoint(x: 600, y: 400), end: CGPoint(x: 970, y: 465), style: textStyle, text: "Frozen frame · ready to share"))
state.annotations.append(Annotation(tool: .arrow, start: CGPoint(x: 600, y: 200), end: CGPoint(x: 900, y: 350), style: EditorStyle()))
d.commit(state)
let image = d.render()!
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("annotations.png"))
let canvas = EditorCanvas(document: d)
let toolbar = EditorToolbar(canvas: canvas, session: session)
try toolbar.writePreview(directory.appendingPathComponent("toolbar.png"))
print("PASS offscreen toolbar and annotated-image previews generated")

let interactionDocument = EditorDocument(image: tests.fixture(), size: CGSize(width: 640, height: 400))
let interactionCanvas = EditorCanvas(document: interactionDocument)
interactionCanvas.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
let interactionWindow = EditorWindow(contentRect: interactionCanvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
interactionWindow.isReleasedWhenClosed = false
interactionWindow.contentView = interactionCanvas
func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: shift ? [.shift] : [],
        timestamp: 0, windowNumber: interactionWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
func drag(_ x: CGFloat, _ y: CGFloat, _ ex: CGFloat, _ ey: CGFloat, shift: Bool = false) {
    interactionCanvas.mouseDown(with: event(.leftMouseDown, x, y, shift: shift))
    interactionCanvas.mouseDragged(with: event(.leftMouseDragged, ex, ey, shift: shift))
    interactionCanvas.mouseUp(with: event(.leftMouseUp, ex, ey, shift: shift))
}
interactionCanvas.choose(.arrow)
drag(50, 50, 180, 110)
XCTAssertEqual(interactionDocument.state.annotations.count, 1)
interactionCanvas.choose(.select)
drag(115, 80, 125, 100)
XCTAssertEqual(interactionDocument.state.annotations[0].start, CGPoint(x: 60, y: 70))
interactionCanvas.duplicate()
XCTAssertEqual(interactionDocument.state.annotations.count, 2)
interactionCanvas.deleteSelected()
XCTAssertEqual(interactionDocument.state.annotations.count, 1)
interactionCanvas.history(redo: false)
XCTAssertEqual(interactionDocument.state.annotations.count, 2)
interactionCanvas.choose(.crop)
drag(200, 120, 400, 280)
XCTAssertEqual(interactionCanvas.pendingCrop, CGRect(x: 200, y: 120, width: 200, height: 160))
drag(250, 160, 270, 180)
XCTAssertEqual(interactionCanvas.pendingCrop, CGRect(x: 220, y: 140, width: 200, height: 160))
interactionCanvas.applyCrop()
XCTAssertEqual(interactionDocument.render(cropped: true)!.width, 200)
interactionCanvas.history(redo: false)
XCTAssertTrue(interactionDocument.state.crop == nil)
interactionCanvas.choose(.crop)
drag(100, 50, 500, 350)
XCTAssertEqual(interactionCanvas.pendingCrop, CGRect(x: 100, y: 50, width: 400, height: 300))
interactionCanvas.applyCrop()
XCTAssertEqual(interactionDocument.render(cropped: true)!.width, 400)
interactionCanvas.history(redo: false)
XCTAssertTrue(interactionDocument.state.crop == nil)
interactionCanvas.choose(.ellipse)
drag(400, 50, 500, 110, shift: true)
XCTAssertEqual(interactionDocument.state.annotations.last!.rect.width, 60)
XCTAssertEqual(interactionDocument.state.annotations.last!.rect.height, 60)
interactionCanvas.choose(.text)
interactionCanvas.mouseDown(with: event(.leftMouseDown, 350, 300))
let textEditor = interactionCanvas.subviews.compactMap { $0 as? NSTextView }.first!
textEditor.string = "Hello\nWorld"
XCTAssertTrue(interactionCanvas.textView(textEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
XCTAssertTrue(interactionCanvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
XCTAssertEqual(interactionDocument.state.annotations.last!.text, "Hello\nWorld")
interactionWindow.close()
print("PASS canvas arrow movement, duplicate/delete, crop adjustment/undo, Shift-circle and Enter-to-finish text")

let quickDocument = EditorDocument(image: tests.fixture(), size: CGSize(width: 640, height: 400))
let quickCanvas = EditorCanvas(document: quickDocument)
quickCanvas.frame = quickDocument.fullRect
let quickWindow = EditorWindow(contentRect: quickCanvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
quickWindow.contentView = quickCanvas
quickCanvas.quickCropOnRelease = true
var quickExports = 0
quickCanvas.onQuickCrop = { quickExports += 1 }
func quickEvent(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
        timestamp: 0, windowNumber: quickWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
quickCanvas.mouseDown(with: quickEvent(.leftMouseDown, 40, 40))
quickCanvas.mouseDragged(with: quickEvent(.leftMouseDragged, 240, 190))
quickCanvas.mouseUp(with: quickEvent(.leftMouseUp, 240, 190))
pump(0.05)
XCTAssertEqual(quickExports, 1)
XCTAssertEqual(quickDocument.render(cropped: true)!.width, 200)
quickWindow.close()
print("PASS initial quick-selection exports on release and confirmed crop can later expand")

XCTAssertEqual(EditorColor(hex: "5785d1")!.hex, "5785D1")
XCTAssertTrue(EditorColor(hex: "#5785D1") == nil)
XCTAssertTrue(EditorColor(hex: "XYZ123") == nil)
let retina = EditorDocument(image: tests.fixture(), size: CGSize(width: 320, height: 200))
let pickCanvas = EditorCanvas(document: retina)
pickCanvas.choose(.picker)
XCTAssertEqual(EditorColor(pickCanvas.sampledColor(CGPoint(x: 20, y: 180))!).hex, "000000")
XCTAssertEqual(EditorColor(pickCanvas.sampledColor(CGPoint(x: 20, y: 20))!).hex, "FFFFFF")
XCTAssertEqual(EditorColor(pickCanvas.sampledColor(CGPoint(x: 320, y: 200))!).hex, "FFFFFF")
print("PASS six-digit hex validation and exact Retina pixel orientation/edge clamping")
pickCanvas.frame = retina.fullRect
pickCanvas.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 150, y: 100),
    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
let lensRep = pickCanvas.bitmapImageRepForCachingDisplay(in: pickCanvas.bounds)!
pickCanvas.cacheDisplay(in: pickCanvas.bounds, to: lensRep)
try lensRep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("pixel-lens.png"))

let clipboard = NSPasteboard(name: NSPasteboard.Name("ShotKey.tests." + UUID().uuidString))
clipboard.clearContents()
clipboard.setData(NSBitmapImageRep(cgImage: tests.fixture()).representation(using: .png, properties: [:])!, forType: .png)
let clipboardSession = EditorSession()
clipboardSession.openClipboard(pasteboard: clipboard)
XCTAssertTrue(clipboardSession.phase == .editing)
XCTAssertTrue(clipboardSession.outputMode == .clipboardOnly)
clipboardSession.outputMode = .fileOnly
XCTAssertTrue(Preferences.shared.outputMode == .both)
clipboardSession.outputMode = .clipboardOnly
clipboardSession.requestCancel()
XCTAssertTrue(clipboardSession.phase == .idle)
XCTAssertTrue(clipboardSession.hasLastEdit)
clipboardSession.openClipboard(pasteboard: clipboard)
XCTAssertTrue(clipboardSession.phase == .editing)
XCTAssertTrue(clipboardSession.hasLastEdit)
clipboardSession.resumeLastEdit()
XCTAssertTrue(clipboardSession.phase == .editing)
XCTAssertTrue(!clipboardSession.hasLastEdit)
clipboardSession.cancel()
XCTAssertTrue(clipboardSession.phase == .idle)
clipboardSession.openClipboard(pasteboard: clipboard)
clipboardSession.finish()
XCTAssertTrue(clipboardSession.phase == .idle)
XCTAssertEqual(CaptureService.shared.results.last!.width, 640)
clipboard.releaseGlobally()
print("PASS independent clipboard output, clean new edit, explicit restore and export")

let ocrDocument = EditorDocument(image: tests.fixture(width: 1000, height: 400), size: CGSize(width: 1000, height: 400))
var ocrState = EditorState()
var ocrStyle = EditorStyle(); ocrStyle.color = EditorColor(.black); ocrStyle.fontSize = 34
ocrState.annotations.append(Annotation(tool: .text, start: CGPoint(x: 530, y: 220),
    end: CGPoint(x: 990, y: 390), style: ocrStyle, text: "First line\nSecond line"))
ocrDocument.commit(ocrState)
let recognized = try EditorOCR.recognize(ocrDocument.render()!)
XCTAssertTrue(recognized.contains("First line\nSecond line"))
print("PASS local Vision OCR recognizes text and retains line breaks")

if CommandLine.arguments.contains("--preview") {
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 700),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "ShotKey Editor Preview"
    canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
    window.contentView = canvas
    canvas.choose(.rectangle); toolbar.refresh()
    window.center(); window.makeKeyAndOrderFront(nil)
    toolbar.presentPreview(window)
    print("PREVIEW_WINDOW \(window.windowNumber)")
    fflush(stdout)
    Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in app.stop(nil) }
    app.run()
}
