import AppKit

// Clausa's app icon: the wordmark's serif "C" and blue full stop, on the
// app's warm paper — the light theme, so the icon and the app are one thing.
// 1024x1024, fully opaque (App Store icons may not have an alpha channel);
// iOS applies the rounded corners itself.
let side = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// RGB with the fourth byte skipped: an opaque image with no alpha channel.
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let rect = CGRect(x: 0, y: 0, width: side, height: side)

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Warm paper, with the faint apricot light the app sits under, from the upper left.
ctx.setFillColor(rgb(0xF7F2EC)); ctx.fill(rect)
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [rgb(0xFBE0CC), rgb(0xF9EADF), rgb(0xF7F2EC)] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 800), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 800), endRadius: 950, options: [.drawsAfterEndLocation])

// The letter, in Newsreader (SIL Open Font License, scripts/fonts). Not Apple's
// New York: its licence covers app interfaces, not logos or marketing.
let fontURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("fonts/Newsreader.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let variation: [NSNumber: NSNumber] = [0x7767_6874: 720, 0x6F70_737A: 72]   // wght, opsz
let descriptor = NSFontDescriptor(fontAttributes: [.family: "Newsreader",
    NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): variation])
guard let font = NSFont(descriptor: descriptor, size: 700), font.familyName == "Newsreader" else {
    fatalError("Newsreader not found at \(fontURL.path)")
}
// Placed by the letter's ink, not its line box, so the mark is centred whatever
// the font's metrics: the C centred on its height, the full stop on its baseline.
let letter = NSAttributedString(string: "C", attributes: [
    .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0x1C1B20),
])
let line = CTLineCreateWithAttributedString(letter)
let ink = CTLineGetImageBounds(line, ctx)
let dot: CGFloat = 100, gap: CGFloat = 22
let left = (CGFloat(side) - (ink.width + gap + dot)) / 2 - ink.minX
let baseline = (CGFloat(side) - ink.height) / 2 - ink.minY
ctx.textPosition = CGPoint(x: left, y: baseline)
CTLineDraw(line, ctx)

// The full stop, in the blue that means "cited" throughout the app.
ctx.setFillColor(rgb(0x2A5BD7))
ctx.fillEllipse(in: CGRect(x: left + ink.maxX + gap, y: baseline, width: dot, height: dot))

NSGraphicsContext.restoreGraphicsState()
import ImageIO
import UniformTypeIdentifiers
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
