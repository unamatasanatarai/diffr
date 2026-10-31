import AppKit

func generateDMGBackground(scale: CGFloat, outputPath: String) {
    let ptWidth: CGFloat = 660
    let ptHeight: CGFloat = 400
    let pxWidth = Int(ptWidth * scale)
    let pxHeight = Int(ptHeight * scale)
    
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxWidth,
        pixelsHigh: pxHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pxWidth * 4,
        bitsPerPixel: 32
    )!
    rep.size = NSSize(width: ptWidth, height: ptHeight)
    
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create NSGraphicsContext")
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    
    // Invert coordinate system to match top-left (0,0)
    cg.translateBy(x: 0, y: ptHeight)
    cg.scaleBy(x: 1.0, y: -1.0)
    
    func gray(_ w: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
        return NSColor(white: w, alpha: a)
    }
    
    // 1. Sleek, premium grayscale gradient (Apple Studio / Platinum finish)
    let bgGrad = NSGradient(starting: gray(0.99), ending: gray(0.93))!
    bgGrad.draw(in: CGRect(x: 0, y: 0, width: ptWidth, height: ptHeight), angle: 90)
    
    // 2. Perimeter hairline border
    let border = NSBezierPath(rect: CGRect(x: 0.5, y: 0.5, width: ptWidth - 1, height: ptHeight - 1))
    gray(0.0, 0.08).setStroke()
    border.lineWidth = 1.0
    border.stroke()
    
    // 3. Top subtle highlight sheen
    let sheen = NSBezierPath()
    sheen.move(to: CGPoint(x: 1, y: 1))
    sheen.line(to: CGPoint(x: ptWidth - 1, y: 1))
    gray(1.0, 0.85).setStroke()
    sheen.lineWidth = 1.0
    sheen.stroke()
    
    let yCenter: CGFloat = 196
    
    // 4. Hairline dashed trajectory guide between the two icon zones
    let track = NSBezierPath()
    track.move(to: CGPoint(x: 248, y: yCenter))
    track.line(to: CGPoint(x: 298, y: yCenter))
    track.move(to: CGPoint(x: 362, y: yCenter))
    track.line(to: CGPoint(x: 412, y: yCenter))
    let pattern: [CGFloat] = [3, 4]
    track.setLineDash(pattern, count: 2, phase: 0)
    track.lineWidth = 1.5
    gray(0.0, 0.16).setStroke()
    track.stroke()
    
    // 5. Floating action capsule badge at the center (x=330, y=196)
    let pillRect = CGRect(x: 330 - 28, y: yCenter - 18, width: 56, height: 36)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 18, yRadius: 18)
    
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 3), blur: 10, color: gray(0.0, 0.09).cgColor)
    gray(1.0).setFill()
    pillPath.fill()
    cg.restoreGState()
    
    gray(0.0, 0.09).setStroke()
    pillPath.lineWidth = 1.0
    pillPath.stroke()
    
    // 6. Sculpted directional arrow inside capsule
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 319, y: yCenter))
    arrow.line(to: CGPoint(x: 340, y: yCenter))
    arrow.move(to: CGPoint(x: 333, y: yCenter - 5.5))
    arrow.line(to: CGPoint(x: 340, y: yCenter))
    arrow.line(to: CGPoint(x: 333, y: yCenter + 5.5))
    arrow.lineWidth = 2.2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    gray(0.20).setStroke()
    arrow.stroke()
    
    // 7. Refined minimalist instructional typography
    cg.translateBy(x: 0, y: ptHeight)
    cg.scaleBy(x: 1.0, y: -1.0)
    
    let pStyle = NSMutableParagraphStyle()
    pStyle.alignment = .center
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: gray(0.40),
        .paragraphStyle: pStyle,
        .kern: 1.5
    ]
    let titleStr = NSAttributedString(string: "DRAG TO APPLICATIONS", attributes: titleAttrs)
    titleStr.draw(in: CGRect(x: 210, y: ptHeight - 238, width: 240, height: 16))
    
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG")
    }
    try! pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Generated: \(outputPath) (\(pxWidth)x\(pxHeight))")
}

generateDMGBackground(scale: 1.0, outputPath: "Resources/dmg_background.png")
generateDMGBackground(scale: 2.0, outputPath: "Resources/dmg_background@2x.png")
