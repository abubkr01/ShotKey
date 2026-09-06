import AppKit

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.98, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.44, green: 0.12, blue: 0.94, alpha: 1).cgColor
] as CFArray, locations: [0, 1])!
let rounded = CGPath(roundedRect: canvas.insetBy(dx: 55, dy: 55), cornerWidth: 215, cornerHeight: 215, transform: nil)
context.saveGState()
context.addPath(rounded)
context.clip()
context.drawLinearGradient(bg, start: CGPoint(x: 120, y: 900), end: CGPoint(x: 900, y: 100), options: [])
context.restoreGState()

context.setStrokeColor(NSColor.white.cgColor)
context.setLineWidth(52)
context.setLineCap(.round)
let c: CGFloat = 250
let e: CGFloat = 774
let l: CGFloat = 145
context.move(to: CGPoint(x: c+l, y: e)); context.addLine(to: CGPoint(x: c, y: e)); context.addLine(to: CGPoint(x: c, y: e-l))
context.move(to: CGPoint(x: e-l, y: e)); context.addLine(to: CGPoint(x: e, y: e)); context.addLine(to: CGPoint(x: e, y: e-l))
context.move(to: CGPoint(x: c, y: c+l)); context.addLine(to: CGPoint(x: c, y: c)); context.addLine(to: CGPoint(x: c+l, y: c))
context.move(to: CGPoint(x: e, y: c+l)); context.addLine(to: CGPoint(x: e, y: c)); context.addLine(to: CGPoint(x: e-l, y: c))
context.strokePath()

context.setFillColor(NSColor.white.cgColor)
context.fillEllipse(in: CGRect(x: 442, y: 442, width: 140, height: 140))
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
