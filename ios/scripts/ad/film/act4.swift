import AppKit
import ImageIO

// Act four, 24.0–29.6 s: the real app, then the name.
//  24.00  "In your language." — the phone rises; a cut on every eighth note, eight languages
//  26.10  the phone drops away; the full stop falls and lands on the beat at 26.4
//  26.50  "Clausa." slides out from behind it; 27.15 "Your policies, read back to you."
//  27.90  "Not medical, legal or insurance advice." / "Sample data shown."
// The screens are simulator screenshots of the Debug build's sample data, nothing mocked.

let languages: [(file: String, name: String)] = [
    ("en", "English"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"),
    ("he", "עברית"), ("ar", "العربية"), ("ja", "日本語"), ("th", "ไทย"),
]
var screens: [CGImage] = []

func loadScreens(_ dir: String) {
    screens = languages.map { l in
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(dir)/\(l.file).png") as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(src, 0, nil)!
    }
}

let inYourLanguage = Words("In your language.", fitted("In your language.", 112) { serif($0, .medium) }, C.ink)
let phoneScreen = CGRect(x: 240, y: 360, width: 600, height: 600 * 2868 / 1320)

func drawPhone(_ t: Double) {
    guard t > 23.95, t < 26.6 else { return }
    let rise = CGFloat(1 - spring(t, 24.0, k: 8, f: 10))
    let drop = CGFloat(inCubic((t - 26.08) / 0.34))
    let k = max(0, min(languages.count - 1, Int((t - 24.0) / 0.3)))
    let sinceCut = t - (24.0 + Double(k) * 0.3)
    let bump = k > 0 ? 1 + 0.02 * CGFloat(exp(-14 * sinceCut)) : 1
    let s = phoneScreen
    group(alpha: 1 - Double(drop) * 0.6, center: CGPoint(x: s.midX, y: s.midY), scale: bump, dy: rise * 1900 + drop * 1700) {
        let body = s.insetBy(dx: -16, dy: -16)
        drawCard(body, radius: 104, fill: rgb(0x1A1A1D), shadow: 0.32)
        stroke(rounded(body.insetBy(dx: 1.5, dy: 1.5), 102), rgb(0x4A4A50), width: 2)
        ctx.saveGState()
        ctx.addPath(rounded(s, 88)); ctx.clip()
        drawImage(screens[k], s)
        ctx.restoreGState()
    }
    // The name of the language on screen, swapped on every cut.
    let pill = spring(t, 24.25, k: 9, f: 12)
    if pill > 0 {
        let label = text(languages[k].name, sans(34, .semibold), C.paper)
        let w = label.width + 64, h: CGFloat = 70
        let r = CGRect(x: 540 - w / 2, y: 1690, width: w, height: h)
        group(alpha: min(1, pill * 2) * (1 - Double(drop)), center: CGPoint(x: 540, y: r.midY), scale: CGFloat(0.8 + 0.2 * pill) * bump,
              dy: drop * 300) {
            fill(rounded(r, h / 2), C.ink)
            let swap = CGFloat(outCubic(sinceCut / 0.18))
            ctx.saveGState(); ctx.clip(to: r)
            drawText(label, x: r.minX + 32, baseline: r.midY + (label.ascent - label.descent) / 2 + (1 - swap) * 30,
                     alpha: k == 0 ? 1 : Double(swap))
            ctx.restoreGState()
        }
    }
}

// MARK: The end

let endMark = Wordmark(size: 172)
let endBase: CGFloat = 940
let endLine = Words("Your policies, read back to you.", serif(56, .regular), C.secondary)
let fine1 = text("Not medical, legal or insurance advice.", sans(27), C.tertiary)
let fine2 = text("Sample data shown.", sans(27), C.tertiary)

func drawEnd(_ t: Double) {
    guard t > 26.05 else { return }
    let rest = endMark.dot(cx: 540, baseline: endBase)
    var dot = rest
    if t < 26.4 {
        dot.y = mix(-60, rest.y, inCubic((t - 26.1) / 0.3))
    } else {
        let x = t - 26.4
        dot.y = rest.y - 70 * CGFloat(exp(-6 * x) * abs(sin(9 * x)))
    }
    let push = 1 + 0.025 * CGFloat(clamp((t - 26.4) / 3.2))
    group(center: CGPoint(x: 540, y: 960), scale: push) {
        let ripple = clamp((t - 26.4) / 0.7)
        if ripple > 0, ripple < 1 {
            stroke(circle(rest, 14 + 190 * CGFloat(outCubic(ripple))), C.cited, width: 3, alpha: 0.45 * (1 - ripple))
        }
        endMark.draw(cx: 540, baseline: endBase, p: (t - 26.5) / 0.85, dotAt: dot)
        kinetic(endLine, baseline: endBase + 120, t: t, inAt: 27.15, stagger: 0.06)
    }
    let f = outCubic((t - 27.9) / 0.6)
    drawTextCentered(fine1, cx: 540, baseline: 1745, alpha: f)
    drawTextCentered(fine2, cx: 540, baseline: 1790, alpha: f)
}

func act4(_ t: Double) {
    guard t > 23.9 else { return }
    kinetic(inYourLanguage, baseline: 250, t: t, inAt: 24.06, outAt: 26.12)
    drawPhone(t)
    drawEnd(t)
}
