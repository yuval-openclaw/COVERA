import AppKit
import ImageIO
import UniformTypeIdentifiers

// App Store screenshots: a serif headline over the app's own screen, on the
// app's own warm paper ground. Keep these two colours in step with
// Theme.Palette.background and .ink — a store page in the wrong palette sells
// a product that does not exist.
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
    ctx.setFillColor(CGColor(red: 0xF7/255.0, green: 0xF2/255.0, blue: 0xEC/255.0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // No glow behind the phone. There used to be a dark radial gradient here,
    // which read as depth against the old black ground and as a large black
    // blob against paper. On a light ground the device is lifted by a shadow
    // under it instead, applied where it is drawn below.

    // Headline.
    let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineSpacing = 10
    let font = NSFont(name: "NewYork-Regular", size: 96) ?? NSFont(name: "Georgia", size: 96)!
    let text = NSAttributedString(string: shot.headline, attributes: [
        .font: font, .foregroundColor: NSColor(red: 0x1C/255.0, green: 0x1B/255.0, blue: 0x20/255.0, alpha: 1), .paragraphStyle: style])
    let box = text.boundingRect(with: NSSize(width: 1160, height: 600), options: [.usesLineFragmentOrigin])
    text.draw(with: NSRect(x: 80, y: CGFloat(H) - 170 - box.height, width: 1160, height: box.height + 20),
              options: [.usesLineFragmentOrigin])

    // The screen, scaled into a rounded phone shape with a lit edge.
    let scale: CGFloat = 0.8
    let sw = CGFloat(W) * scale, sh = CGFloat(H) * scale
    let frame = CGRect(x: (CGFloat(W) - sw) / 2, y: -sh * 0.12, width: sw, height: sh)
    let path = CGPath(roundedRect: frame, cornerWidth: 110, cornerHeight: 110, transform: nil)
    // A soft shadow lifts the device off the paper, in place of the old glow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70,
                  color: CGColor(srgbRed: 0.18, green: 0.13, blue: 0.08, alpha: 0.30))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.draw(screen, in: frame); ctx.restoreGState()
    // A fine dark edge, the light-ground counterpart of the old lit white one.
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.14)); ctx.setLineWidth(3); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: "\(outDir)/\(index + 1)-\(shot.file).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print(url.lastPathComponent)
}
