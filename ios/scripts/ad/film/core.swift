import AppKit
import CoreText

// Canvas, palette, type and motion for the Covera ad. Colours are the app's own
// (Theme.Palette, light appearance), so the film and the product are one thing.

let W = 1080, H = 1920
let FPS = 30.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum C {
    static let paper = rgb(0xF7F2EC), surface = rgb(0xFFFCF8), inset = rgb(0xF1EAE1), rule = rgb(0xE4DACD)
    static let ink = rgb(0x1C1B20), secondary = rgb(0x5A5860), tertiary = rgb(0x5B5963)
    static let cited = rgb(0x2A5BD7), amber = rgb(0x8A5A05), coral = rgb(0xC03A2B), ambient = rgb(0xFBE3D2)
    static let night = rgb(0x131215), onNight = rgb(0xF7F2EC), onNight2 = rgb(0xB5AFA8), pulse = rgb(0xFF6A58)
}

// MARK: - Type

func serif(_ size: CGFloat, _ weight: NSFont.Weight = .medium, italic: Bool = false) -> CTFont {
    var d = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    if let s = d.withDesign(.serif) { d = s }
    if italic { d = d.withSymbolicTraits(.italic) }
    return (NSFont(descriptor: d, size: size) ?? NSFont(name: "Georgia", size: size)!) as CTFont
}

func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: weight) as CTFont
}

func attrs(_ font: CTFont, _ color: CGColor, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
    [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color, .kern: kern]
}

/// One line of text as an image, with the metrics to place it by its baseline.
struct TextImage {
    let image: CGImage
    let width, ascent, descent, pad: CGFloat
}

var textCache: [String: TextImage] = [:]

func text(_ s: String, _ font: CTFont, _ color: CGColor, kern: CGFloat = 0) -> TextImage {
    let key = "\(s)|\(CTFontCopyPostScriptName(font))|\(CTFontGetSize(font))|\(color.components ?? [])|\(kern)"
    if let hit = textCache[key] { return hit }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs(font, color, kern: kern)))
    var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l))
    let pad: CGFloat = 10
    let c = CGContext(data: nil, width: Int(ceil(w + 2 * pad)), height: Int(ceil(a + d + 2 * pad)), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.textPosition = CGPoint(x: pad, y: pad + d)
    CTLineDraw(line, c)
    let made = TextImage(image: c.makeImage()!, width: w, ascent: a, descent: d, pad: pad)
    textCache[key] = made
    return made
}

/// Wrapped text as an image; returns the image and its drawn size.
func paragraph(_ s: String, _ font: CTFont, _ color: CGColor, width: CGFloat,
               align: CTTextAlignment = .left, spacing: CGFloat = 6) -> (image: CGImage, size: CGSize) {
    var alignment = align, lineSpacing = spacing
    let settings = [
        CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &alignment),
        CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: &lineSpacing),
    ]
    var a = attrs(font, color)
    a[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = CTParagraphStyleCreate(settings, settings.count)
    let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: s, attributes: a))
    let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: 4000), nil)
    let h = ceil(size.height) + 4
    let c = CGContext(data: nil, width: Int(width), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: h), transform: nil), nil)
    CTFrameDraw(frame, c)
    return (c.makeImage()!, CGSize(width: width, height: h))
}

/// A line split into words, so each can move on its own.
struct Words {
    let parts: [TextImage]
    let xs: [CGFloat]
    let width, ascent, descent: CGFloat
    /// How far above the baseline the letters really reach. The font's own
    /// ascent includes generous line spacing, which would let a mask show a
    /// word after it has left its line.
    let top: CGFloat

    init(_ s: String, _ font: CTFont, _ color: CGColor) {
        parts = s.split(separator: " ").map { text(String($0), font, color) }
        let gap = text("a a", font, color).width - 2 * text("a", font, color).width
        var x: CGFloat = 0, xs: [CGFloat] = []
        for p in parts { xs.append(x); x += p.width + gap }
        self.xs = xs
        width = x - gap
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
        top = CTFontGetCapHeight(font) * 1.22
    }
}

/// The largest size at or under `size` at which the line fits `maxWidth`.
func fitted(_ s: String, _ size: CGFloat, maxWidth: CGFloat = 960, font: (CGFloat) -> CTFont) -> CTFont {
    var z = size
    while z > 20, text(s, font(z), C.ink).width > maxWidth { z -= 4 }
    return font(z)
}

// MARK: - Motion

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
func outCubic(_ x: Double) -> Double { let p = 1 - clamp(x); return 1 - p * p * p }
func outQuint(_ x: Double) -> Double { let p = 1 - clamp(x); return 1 - p * p * p * p * p }
func inCubic(_ x: Double) -> Double { let c = clamp(x); return c * c * c }
func inOutCubic(_ x: Double) -> Double { let c = clamp(x); return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2 }
func mix(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }

/// Damped spring from 0 to 1, starting at `start`; overshoots about 10%.
func spring(_ t: Double, _ start: Double, k: Double = 8, f: Double = 11) -> Double {
    let x = t - start
    return x <= 0 ? 0 : 1 - exp(-k * x) * cos(f * x)
}

func mixColor(_ a: CGColor, _ b: CGColor, _ p: Double) -> CGColor {
    let x = a.components!, y = b.components!
    return CGColor(srgbRed: mix(x[0], y[0], p), green: mix(x[1], y[1], p), blue: mix(x[2], y[2], p), alpha: mix(x[3], y[3], p))
}

// MARK: - Canvas

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!

func setupCanvas() {
    ctx.translateBy(x: 0, y: CGFloat(H))  // top-down, like a screen
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
}

/// Group opacity, multiplied into every draw below it.
var groupAlpha: Double = 1

func group(alpha: Double = 1, center: CGPoint = .zero, scale: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0,
           rotate: CGFloat = 0, _ body: () -> Void) {
    guard alpha > 0.002 else { return }
    let saved = groupAlpha
    groupAlpha *= alpha
    ctx.saveGState()
    ctx.translateBy(x: center.x + dx, y: center.y + dy)
    ctx.rotate(by: rotate)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -center.x, y: -center.y)
    body()
    ctx.restoreGState()
    groupAlpha = saved
}

func drawImage(_ img: CGImage, _ r: CGRect, alpha: Double = 1) {
    let a = alpha * groupAlpha
    guard a > 0.002 else { return }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(a))
    ctx.translateBy(x: r.minX, y: r.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    ctx.restoreGState()
}

/// Places text by its baseline; `x` is where the glyphs begin.
func drawText(_ ti: TextImage, x: CGFloat, baseline: CGFloat, alpha: Double = 1, scale: CGFloat = 1) {
    let h = CGFloat(ti.image.height), w = CGFloat(ti.image.width)
    drawImage(ti.image, CGRect(x: x - ti.pad * scale, y: baseline - (h - ti.pad - ti.descent) * scale,
                               width: w * scale, height: h * scale), alpha: alpha)
}

func drawTextCentered(_ ti: TextImage, cx: CGFloat, baseline: CGFloat, alpha: Double = 1) {
    drawText(ti, x: cx - ti.width / 2, baseline: baseline, alpha: alpha)
}

func fill(_ path: CGPath, _ color: CGColor, alpha: Double = 1) {
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha * groupAlpha))
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, alpha: Double = 1, dash: [CGFloat] = []) {
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha * groupAlpha))
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
    ctx.strokePath()
    ctx.restoreGState()
}

/// The first `fraction` of a polyline, by length — for lines that draw themselves.
func trimmed(_ points: [CGPoint], _ fraction: Double) -> CGPath {
    let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
    var left = lengths.reduce(0, +) * CGFloat(clamp(fraction))
    let path = CGMutablePath()
    path.move(to: points[0])
    for (i, len) in lengths.enumerated() {
        let a = points[i], b = points[i + 1]
        if left >= len { path.addLine(to: b); left -= len; continue }
        path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * left / len, y: a.y + (b.y - a.y) * left / len))
        break
    }
    return path
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.height / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

// MARK: - Cards (shadow baked in once, not blurred every frame)

let shadowPad: CGFloat = 100
var cardCache: [String: CGImage] = [:]

func cardImage(_ w: CGFloat, _ h: CGFloat, radius: CGFloat = 38, fill: CGColor = C.surface,
               shadow: CGFloat = 0.14, border: CGColor? = nil) -> CGImage {
    let key = "\(w)x\(h)|\(radius)|\(fill.components ?? [])|\(shadow)|\(border?.components ?? [])"
    if let hit = cardCache[key] { return hit }
    let c = CGContext(data: nil, width: Int(w + 2 * shadowPad), height: Int(h + 2 * shadowPad), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let path = CGPath(roundedRect: CGRect(x: shadowPad, y: shadowPad, width: w, height: h),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    if shadow > 0 {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -28), blur: 64, color: CGColor(srgbRed: 0.25, green: 0.16, blue: 0.08, alpha: shadow))
        c.addPath(path); c.setFillColor(fill); c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: CGColor(srgbRed: 0.25, green: 0.16, blue: 0.08, alpha: shadow * 0.6))
        c.addPath(path); c.setFillColor(fill); c.fillPath()
        c.restoreGState()
    }
    c.addPath(path); c.setFillColor(fill); c.fillPath()
    if let border { c.addPath(path); c.setStrokeColor(border); c.setLineWidth(2); c.strokePath() }
    let made = c.makeImage()!
    cardCache[key] = made
    return made
}

func drawCard(_ r: CGRect, radius: CGFloat = 38, fill: CGColor = C.surface, shadow: CGFloat = 0.14,
              border: CGColor? = nil, alpha: Double = 1) {
    let img = cardImage(r.width.rounded(), r.height.rounded(), radius: radius, fill: fill, shadow: shadow, border: border)
    drawImage(img, r.insetBy(dx: -shadowPad, dy: -shadowPad), alpha: alpha)
}

/// A capsule label: tinted ground, coloured text, optional leading dot.
func chip(_ label: String, color: CGColor, at origin: CGPoint, size: CGFloat = 30, dot: Bool = false,
          alpha: Double = 1, solid: Bool = false) -> CGFloat {
    let ti = text(label, sans(size, .semibold), solid ? C.paper : color)
    let padX = size * 0.62, h = size * 1.7, dotW: CGFloat = dot ? size * 0.55 : 0
    let r = CGRect(x: origin.x, y: origin.y, width: ti.width + 2 * padX + dotW, height: h)
    let tint = solid ? color : color.copy(alpha: 0.11)!
    fill(rounded(r, h / 2), tint, alpha: alpha)
    if dot { fill(circle(CGPoint(x: r.minX + padX + size * 0.16, y: r.midY), size * 0.16), color, alpha: alpha) }
    drawText(ti, x: r.minX + padX + dotW, baseline: r.midY + (ti.ascent - ti.descent) / 2, alpha: alpha)
    return r.width
}

// MARK: - Kinetic type

/// Words rise into place from behind their own line, one after another, and
/// leave upward the same way. `left` aligns the line's start instead of its centre.
func kinetic(_ w: Words, cx: CGFloat = CGFloat(W) / 2, left: CGFloat? = nil, baseline: CGFloat, t: Double,
             inAt: Double, outAt: Double = .infinity, stagger: Double = 0.065, alpha: Double = 1) {
    guard t > inAt - 0.05, t < outAt + 0.3 + Double(w.parts.count) * stagger else { return }
    let lineH = w.top + w.descent
    let x0 = left ?? cx - w.width / 2
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x0 - 60, y: baseline - w.top - 6, width: w.width + 120, height: lineH + 12))
    for (i, p) in w.parts.enumerated() {
        let a = outQuint((t - inAt - Double(i) * stagger) / 0.62)
        let b = inCubic((t - outAt - Double(i) * stagger * 0.5) / 0.28)
        guard a > 0, b < 1 else { continue }
        let dy = (1 - CGFloat(a)) * (lineH + 16) - CGFloat(b) * (lineH + 16)
        drawText(p, x: x0 + w.xs[i], baseline: baseline + dy, alpha: alpha * min(1, a * 1.4))
    }
    ctx.restoreGState()
}

// MARK: - The wordmark: "Covera" and its blue full stop, drawn as a dot so it can move

struct Wordmark {
    let name: TextImage
    let dotR, gap: CGFloat

    init(size: CGFloat) {
        name = text("Covera", serif(size, .semibold), C.ink)
        dotR = size * 0.078
        gap = size * 0.035
    }

    var width: CGFloat { name.width + gap + 2 * dotR }

    func dot(cx: CGFloat, baseline: CGFloat) -> CGPoint {
        CGPoint(x: cx - width / 2 + name.width + gap + dotR, y: baseline - dotR)
    }

    /// Letters slide out leftward from behind the dot as `p` goes 0 → 1.
    func draw(cx: CGFloat, baseline: CGFloat, p: Double, dotAt: CGPoint? = nil, dotScale: CGFloat = 1) {
        let x0 = cx - width / 2
        let d = dot(cx: cx, baseline: baseline)
        if p > 0 {
            let reveal = CGFloat(outQuint(p))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: d.x - dotR - (name.width + 80) * reveal, y: baseline - name.ascent - 30,
                                width: (name.width + 80) * reveal, height: name.ascent + name.descent + 60))
            drawText(name, x: x0 + (1 - reveal) * 140, baseline: baseline, alpha: min(1, Double(reveal) * 1.6))
            ctx.restoreGState()
        }
        fill(circle(dotAt ?? d, dotR * dotScale), C.cited)
    }
}
