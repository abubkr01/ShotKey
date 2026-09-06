import AppKit

// Lightweight runner for Macs with Command Line Tools but no XCTest framework.
class XCTestCase {}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "\(a) != \(b)", file: file, line: line) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a < b, "\(a) is not < \(b)", file: file, line: line) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a > b, "\(a) is not > \(b)", file: file, line: line) }
struct TestShortcut { var readable = "⌥1" }
struct TestOutput { var title = "Save + Copy to Clipboard" }
class Preferences {
    static let shared = Preferences()
    let regionShortcut = TestShortcut()
    let outputMode = TestOutput()
}
class CaptureService {
    static let shared = CaptureService()
    var results: [CGImage] = []
    func deliver(_ image: CGImage) { results.append(image) }
    func deliverOnMain(_ image: CGImage) -> Bool { results.append(image); return true }
}
class AppDelegate {
    static var shared: AppDelegate? = AppDelegate()
    func showError(_ error: Error) { print("Capture error: \(error)") }
    func showErrorMessage(_ message: String) { print(message) }
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
XCTAssertTrue(session.phase == .idle)
XCTAssertEqual(CaptureService.shared.results.count, 1)
session.toggle()
session.cancel()
pump(0.2)
XCTAssertTrue(session.phase == .idle)
XCTAssertEqual(CaptureService.shared.results.count, 1)
print("PASS repeated hotkey during loading, second press finishes once, cancelled capture cannot reopen")

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
interactionCanvas.choose(.ellipse)
drag(400, 50, 500, 110, shift: true)
XCTAssertEqual(interactionDocument.state.annotations.last!.rect.width, 60)
XCTAssertEqual(interactionDocument.state.annotations.last!.rect.height, 60)
interactionCanvas.choose(.text)
interactionCanvas.mouseDown(with: event(.leftMouseDown, 350, 300))
let textEditor = interactionCanvas.subviews.compactMap { $0 as? NSTextView }.first!
textEditor.string = "Hello\nWorld"
interactionCanvas.commitText()
XCTAssertEqual(interactionDocument.state.annotations.last!.text, "Hello\nWorld")
interactionWindow.close()
print("PASS canvas arrow movement, duplicate/delete, crop adjustment/undo, Shift-circle and multiline text")

if CommandLine.arguments.contains("--preview") {
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 700),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "ShotKey Editor Preview"
    canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
    window.contentView = canvas
    window.center(); window.makeKeyAndOrderFront(nil)
    toolbar.presentPreview(window)
    print("PREVIEW_WINDOW \(window.windowNumber)")
    fflush(stdout)
    Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in app.stop(nil) }
    app.run()
}
