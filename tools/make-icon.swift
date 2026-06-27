import AppKit

// Draws a 1024x1024 app icon using Core Graphics and saves it as PNG.
// Concept: teal→cyan gradient rounded rectangle + white flow glyph (node→diamond→2 nodes).
// Usage: swift make-icon.swift <out.png>

let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("context")
}

let S = CGFloat(size)
func fy(_ y: CGFloat) -> CGFloat { S - y } // top-down y → CG(bottom-left) y
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: fy(y)) }

// Background: rounded rectangle + gradient
let inset: CGFloat = 76
let bg = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.059, green: 0.463, blue: 0.431, alpha: 1), // teal-700 (top)
    CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 1)   // teal-300 (bottom)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Common style for white glyphs
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.setStrokeColor(white)
ctx.setFillColor(white)
ctx.setLineWidth(26)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

func roundedNode(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
    let r = CGRect(x: cx - w/2, y: fy(cy) - h/2, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.strokePath()
}
func diamond(cx: CGFloat, cy: CGFloat, half: CGFloat) {
    ctx.beginPath()
    ctx.move(to: P(cx, cy - half))
    ctx.addLine(to: P(cx + half, cy))
    ctx.addLine(to: P(cx, cy + half))
    ctx.addLine(to: P(cx - half, cy))
    ctx.closePath()
    ctx.strokePath()
}
// line from p1→p2 + arrowhead at p2
func arrow(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
    let dx = x2 - x1, dy = y2 - y1
    let len = max(1, (dx*dx + dy*dy).squareRoot())
    let ux = dx/len, uy = dy/len
    let head: CGFloat = 40
    let bx = x2 - ux*head, by = y2 - uy*head // line stops just before the arrowhead
    ctx.beginPath(); ctx.move(to: P(x1, y1)); ctx.addLine(to: P(bx, by)); ctx.strokePath()
    // arrowhead (filled triangle)
    let px = -uy, py = ux // perpendicular unit vector
    let w: CGFloat = 26
    ctx.beginPath()
    ctx.move(to: P(x2, y2))
    ctx.addLine(to: P(bx + px*w, by + py*w))
    ctx.addLine(to: P(bx - px*w, by - py*w))
    ctx.closePath(); ctx.fillPath()
}

// Layout (top-down coordinates)
let topC = (x: CGFloat(512), y: CGFloat(258))
let dia  = (x: CGFloat(512), y: CGFloat(500), half: CGFloat(116))
let blC  = (x: CGFloat(366), y: CGFloat(792))
let brC  = (x: CGFloat(658), y: CGFloat(792))
let nodeW: CGFloat = 232, nodeH: CGFloat = 150
let smW: CGFloat = 206, smH: CGFloat = 136

roundedNode(cx: topC.x, cy: topC.y, w: nodeW, h: nodeH)
diamond(cx: dia.x, cy: dia.y, half: dia.half)
roundedNode(cx: blC.x, cy: blC.y, w: smW, h: smH)
roundedNode(cx: brC.x, cy: brC.y, w: smW, h: smH)

// Connecting arrows
arrow(topC.x, topC.y + nodeH/2, dia.x, dia.y - dia.half)             // top → diamond
arrow(dia.x - dia.half*0.55, dia.y + dia.half*0.55, blC.x, blC.y - smH/2) // diamond → bottom-left
arrow(dia.x + dia.half*0.55, dia.y + dia.half*0.55, brC.x, brC.y - smH/2) // diamond → bottom-right

// Save PNG
guard let img = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
