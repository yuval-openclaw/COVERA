import AppKit
import ImageIO
import UniformTypeIdentifiers

// App Store screenshots: a serif headline over the app's own screen, on black.
// Usage: swift make_store_screenshots.swift <raw dir> <out dir>
// Raw shots come from a demo launch: -CoveraDemo -CoveraShot <name>.
let W = 1320, H = 2868
let shots: [(file: String, headline: String)] = [
    ("home", "Your insurance,\nfinally readable."),
    ("plan", "A plan, step by step,\nwhen something happens."),
    ("policies", "Every policy you own,\nin one wallet."),
    ("ask", "Ask anything.\nEvery answer shows its page."),
    ("calllog", "A record of\nevery call you make."),
]
let rawDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

for (index, shot) in shots.enumerated() {
    guard let source = NSImage(contentsOfFile: "\(rawDir)/\(shot.file).png"),
          let screen = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Soft glow behind the phone.
    let glow = CGGradient(colorsSpace: space,
        colors: [CGColor(srgbRed: 0.11, green: 0.12, blue: 0.17, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: 1100), startRadius: 0,
                           endCenter: CGPoint(x: W / 2, y: 1100), endRadius: 1400, options: [])

    // Headline.
    let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineSpacing = 10
    let font = NSFont(name: "NewYork-Regular", size: 96) ?? NSFont(name: "Georgia", size: 96)!
    let text = NSAttributedString(string: shot.headline, attributes: [
        .font: font, .foregroundColor: NSColor(white: 0.96, alpha: 1), .paragraphStyle: style])
    let box = text.boundingRect(with: NSSize(width: 1160, height: 600), options: [.usesLineFragmentOrigin])
    text.draw(with: NSRect(x: 80, y: CGFloat(H) - 170 - box.height, width: 1160, height: box.height + 20),
              options: [.usesLineFragmentOrigin])

    // The screen, scaled into a rounded phone shape with a lit edge.
    let scale: CGFloat = 0.8
    let sw = CGFloat(W) * scale, sh = CGFloat(H) * scale
    let frame = CGRect(x: (CGFloat(W) - sw) / 2, y: -sh * 0.12, width: sw, height: sh)
    let path = CGPath(roundedRect: frame, cornerWidth: 110, cornerHeight: 110, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.draw(screen, in: frame); ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); ctx.setLineWidth(4); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: "\(outDir)/\(index + 1)-\(shot.file).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print(url.lastPathComponent)
}
