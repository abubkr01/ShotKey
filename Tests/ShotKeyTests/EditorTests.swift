import AppKit

final class EditorTests: XCTestCase {
    func fixture(width: Int = 640, height: Int = 400) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(NSColor.white.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.setFillColor(NSColor.black.cgColor)
        c.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        return c.makeImage()!
    }
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = c.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { ptr[y * image.width * 4 + x * 4 + $0] }
    }
    func testFiveHundredUndoRedoAndBranchingHistory() {
        let d = EditorDocument(image: fixture(), size: CGSize(width: 640, height: 400))
        for i in 0..<500 {
            var state = d.state
            state.annotations.append(Annotation(tool: .arrow, start: .zero,
                end: CGPoint(x: i + 5, y: 30), style: EditorStyle()))
            d.commit(state)
        }
        for _ in 0..<500 { d.undo() }
        XCTAssertTrue(d.state.annotations.isEmpty)
        for _ in 0..<500 { d.redo() }
        XCTAssertEqual(d.state.annotations.count, 500)
        d.undo()
        var state = d.state; state.crop = CGRect(x: 10, y: 10, width: 100, height: 80)
        d.commit(state)
        XCTAssertTrue(d.redoStates.isEmpty)
        let count = d.undoStates.count
        d.commit(d.state)
        XCTAssertEqual(d.undoStates.count, count)
    }
    func testRetinaCropDimensionsAndTopLeftOrientation() {
        let d = EditorDocument(image: fixture(), size: CGSize(width: 320, height: 200))
        var state = d.state; state.crop = CGRect(x: 0, y: 150, width: 80, height: 50)
        d.commit(state)
        let image = d.render(cropped: true)!
        XCTAssertEqual(image.width, 160)
        XCTAssertEqual(image.height, 100)
        XCTAssertLessThan(pixel(image, 20, 20)[0], 5)
        d.undo()
        XCTAssertEqual(d.render(cropped: true)!.width, 640)
        d.redo()
        XCTAssertEqual(d.render(cropped: true)!.height, 100)
    }
    func testFilledRectangleAndEllipseDoNotChangeOutsidePixels() {
        let d = EditorDocument(image: fixture(), size: CGSize(width: 640, height: 400))
        var style = EditorStyle(); style.fill = EditorColor(.red); style.fillMode = 1
        var state = d.state
        state.annotations = [Annotation(tool: .rectangle, start: CGPoint(x: 400, y: 200),
            end: CGPoint(x: 500, y: 300), style: style)]
        d.commit(state)
        let image = d.render()!
        let inside = pixel(image, 450, 150)
        XCTAssertGreaterThan(inside[0], 245)
        XCTAssertLessThan(inside[1], 10)
        XCTAssertGreaterThan(pixel(image, 600, 350)[1], 245)
        state.annotations[0].tool = .ellipse
        d.commit(state)
        let ellipse = d.render()!
        XCTAssertGreaterThan(pixel(ellipse, 401, 101)[1], 240)
        XCTAssertLessThan(pixel(ellipse, 450, 150)[1], 10)
    }
    func testBlurAffectsOnlyRequestedRectangle() {
        let d = EditorDocument(image: fixture(), size: CGSize(width: 640, height: 400))
        var state = d.state
        state.annotations = [Annotation(tool: .blur, start: CGPoint(x: 280, y: 250),
            end: CGPoint(x: 360, y: 350), style: EditorStyle())]
        d.commit(state)
        let image = d.render()!
        let boundary = pixel(image, 319, 100)[0]
        XCTAssertGreaterThan(boundary, 30)
        XCTAssertLessThan(boundary, 225)
        XCTAssertLessThan(pixel(image, 319, 20)[0], 5)
    }
    func testStyleSerializationRetainsIndependentToolSettings() throws {
        var style = EditorStyle()
        style.fillMode = 2; style.fontSize = 63; style.width = 8
        style.textBackground = true; style.textOutline = 3; style.blur = 29
        style.color = EditorColor(.blue)
        let restored = try JSONDecoder().decode(EditorStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(restored, style)
        XCTAssertEqual(EditorTool.key("a"), .arrow)
        XCTAssertEqual(EditorTool.key("c"), .crop)
        let suite = "ShotKey.EditorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        style.save(.arrow, defaults: defaults)
        var rectangle = style; rectangle.color = EditorColor(.red); rectangle.fillMode = 1
        rectangle.save(.rectangle, defaults: defaults)
        XCTAssertEqual(EditorStyle.load(.arrow, defaults: defaults), style)
        XCTAssertEqual(EditorStyle.load(.rectangle, defaults: defaults), rectangle)
    }
}
