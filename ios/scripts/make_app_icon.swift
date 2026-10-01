import AppKit

// Covera's app icon: the wordmark's serif "C" and blue full stop, on the
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

// The letter, in the app's serif.
let font = NSFont(name: "NewYorkLarge-Semibold", size: 700)
    ?? NSFont(name: "NewYork-Semibold", size: 700)
    ?? NSFont(name: "Georgia-Bold", size: 700)!
let letter = NSAttributedString(string: "C", attributes: [
    .font: font, .foregroundColor: NSColor(cgColor: rgb(0x1C1B20))!, .kern: 0,
])
let size = letter.size()
let origin = CGPoint(x: (CGFloat(side) - size.width) / 2 - 60, y: (CGFloat(side) - size.height) / 2 + 10)
letter.draw(at: origin)

// The full stop, in the blue that means "cited" throughout the app.
let dot: CGFloat = 104
let dotRect = CGRect(x: origin.x + size.width + 18, y: origin.y + font.descender * -1 + 38, width: dot, height: dot)
ctx.setFillColor(rgb(0x2A5BD7))
ctx.fillEllipse(in: dotRect)

NSGraphicsContext.restoreGraphicsState()
import ImageIO
import UniformTypeIdentifiers
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
