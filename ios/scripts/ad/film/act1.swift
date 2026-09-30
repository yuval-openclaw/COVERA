import AppKit

// Act one, 0–9.6 s: the problem on a dark ground, then the reveal.
//   0.00  "Your health insurance policy is" / "48 pages."  — pages pile up, one click each
//   2.55  "Nobody reads it."  — the pile blows away
//   3.62  "Until the day" / "you need it."
//   4.80  a heartbeat line; one word per beat: surgery, diagnosis, accident, baby
//   7.20  the pulse becomes the full stop of "Covera." and the paper floods in

let revealMark = Wordmark(size: 190)
let revealBase: CGFloat = 1010
let revealDot = revealMark.dot(cx: 540, baseline: revealBase)

// MARK: Background

func radial(_ center: CGPoint, _ radius: CGFloat, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}

func paperGlow(_ t: Double) {
    let g = CGGradient(colorsSpace: space, colors: [C.ambient, C.ambient.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    let top = CGPoint(x: 540 + 170 * CGFloat(sin(t * 0.33)), y: -140)
    ctx.drawRadialGradient(g, startCenter: top, startRadius: 0, endCenter: top, endRadius: 1450, options: [])
    let low = CGPoint(x: 980 - 120 * CGFloat(sin(t * 0.21)), y: 2050)
    ctx.saveGState(); ctx.setAlpha(0.55)
    ctx.drawRadialGradient(g, startCenter: low, startRadius: 0, endCenter: low, endRadius: 950, options: [])
    ctx.restoreGState()
}

func background(_ t: Double) {
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    let wipe = inOutCubic((t - 7.2) / 0.6)
    if wipe < 1 {
        ctx.setFillColor(C.night); ctx.fill(full)
        radial(CGPoint(x: 540, y: 940), 1150, rgb(0x2A2629), C.night)
    }
    guard wipe > 0 else { return }
    ctx.saveGState()
    if wipe < 1 { ctx.addPath(circle(revealDot, CGFloat(wipe) * 2300)); ctx.clip() }
    ctx.setFillColor(C.paper); ctx.fill(full)
    paperGlow(t)
    ctx.restoreGState()
}

// MARK: The pile of pages

struct Rand {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(s >> 11) / Double(1 << 53))
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

struct Sheet { let land, from: CGPoint; let rot0, rot, vx, vy, spin: CGFloat; let variant: Int }

let sheets: [Sheet] = {
    var r = Rand(s: 42)
    return (0..<48).map { i in
        let land = CGPoint(x: 540 + r.range(-80, 80), y: 1390 + r.range(-36, 36) - CGFloat(i) * 1.4)
        let rot = r.range(-0.15, 0.15)
        return Sheet(land: land, from: CGPoint(x: land.x + r.range(-320, 320), y: 2350), rot0: rot + r.range(-0.7, 0.7),
                     rot: rot, vx: r.range(-900, 900), vy: r.range(1500, 2700), spin: r.range(-5, 5), variant: i % 3)
    }
}()

let sheetW: CGFloat = 330, sheetH: CGFloat = 430

let sheetImages: [CGImage] = (0..<3).map { v in
    let pad: CGFloat = 60
    let c = CGContext(data: nil, width: Int(sheetW + 2 * pad), height: Int(sheetH + 2 * pad), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let r = CGRect(x: pad, y: pad, width: sheetW, height: sheetH)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.55))
    c.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
    c.setFillColor(rgb(0xEFE8DF)); c.fillPath()
    c.restoreGState()
    var rr = Rand(s: UInt64(7 + v))
    c.setFillColor(rgb(0xB9AFA3)); c.fill(CGRect(x: pad + 30, y: pad + sheetH - 58, width: 150 + CGFloat(v) * 20, height: 16))
    c.setFillColor(rgb(0xD4CBBF))
    var y = pad + sheetH - 100
    while y > pad + 36 {
        let full = rr.next() > 0.18
        c.fill(CGRect(x: pad + 30, y: y, width: full ? sheetW - 60 : rr.range(80, 200), height: 8))
        y -= full ? 22 : 38
    }
    return c.makeImage()!
}

func landTime(_ i: Int) -> Double { 0.8 + Double(i) * 0.021 }

func drawSheets(_ t: Double) {
    guard t > 0.35, t < 3.8 else { return }
    for (i, s) in sheets.enumerated() {
        let tl = landTime(i)
        guard t > tl - 0.4 else { continue }
        let p = outCubic((t - (tl - 0.4)) / 0.4)
        var pos = CGPoint(x: mix(s.from.x, s.land.x, p), y: mix(s.from.y, s.land.y, p))
        var rot = mix(s.rot0, s.rot, p)
        let blow = t - (2.5 + Double(47 - i) * 0.005)   // the top of the pile goes first, downward
        if blow > 0 {
            let b = CGFloat(blow)
            pos.x += s.vx * (0.25 * b + 1.3 * b * b)
            pos.y += s.vy * (0.25 * b + 1.3 * b * b)
            rot += s.spin * b
        }
        guard pos.y < 2400, pos.x > -500, pos.x < 1580 else { continue }
        ctx.saveGState()
        ctx.translateBy(x: pos.x, y: pos.y); ctx.rotate(by: rot)
        let img = sheetImages[s.variant]
        drawImage(img, CGRect(x: -CGFloat(img.width) / 2, y: -CGFloat(img.height) / 2,
                              width: CGFloat(img.width), height: CGFloat(img.height)))
        ctx.restoreGState()
    }
}

// MARK: Opening lines

let lineIntro = Words("Your health insurance policy is", serif(58, .regular), C.onNight2)
let pagesWord = text("pages.", serif(176, .medium), C.onNight)
let nobody = Words("Nobody reads it.", fitted("Nobody reads it.", 150) { serif($0, .medium) }, C.onNight)
let untilA = Words("Until the day", serif(128, .medium), C.onNight)
let untilB = Words("you need it.", serif(128, .medium), C.onNight)
let events = ["Surgery.", "A diagnosis.", "An accident.", "A new baby."].map {
    Words($0, fitted($0, 150) { serif($0, .medium) }, C.onNight)
}

/// "48 pages.", counting up as the pages land. The number is right-aligned so
/// "pages." never moves while it counts.
func drawCounter(_ t: Double) {
    let font = serif(176, .medium)
    let full = text("48", font, C.onNight).width + 44 + pagesWord.width
    let numRight = 540 - full / 2 + text("48", font, C.onNight).width
    let baseline: CGFloat = 800
    let a = outQuint((t - 0.72) / 0.62), b = inCubic((t - 2.36) / 0.28)
    guard a > 0, b < 1 else { return }
    let landed = sheets.indices.filter { landTime($0) <= t }.count
    let number = text("\(max(1, landed))", font, C.onNight)
    let top = CTFontGetCapHeight(font) * 1.22
    let lineH = top + pagesWord.descent
    let dy = (1 - CGFloat(a)) * (lineH + 16) - CGFloat(b) * (lineH + 16)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: baseline - top - 6, width: CGFloat(W), height: lineH + 12))
    drawText(number, x: numRight - number.width, baseline: baseline + dy)
    drawText(pagesWord, x: numRight + 44, baseline: baseline + dy)
    ctx.restoreGState()
}

// MARK: The heartbeat line

let ecgBeats = [4.8, 5.4, 6.0, 6.6]
let ecgStart = 4.45, ecgEnd = 7.2

func headX(_ t: Double) -> CGFloat { mix(-60, revealDot.x, (t - ecgStart) / (ecgEnd - ecgStart)) }

func ecgY(_ x: CGFloat) -> CGFloat {
    var y = revealDot.y
    for b in ecgBeats {
        let u = x - headX(b)
        y -= 16 * exp(-pow((u + 72) / 16, 2))
        if u > -16, u <= -6 { y += (u + 16) / 10 * 14 }
        else if u > -6, u <= 0 { y += 14 - (u + 6) / 6 * 214 }
        else if u > 0, u <= 9 { y += -200 + u / 9 * 260 }
        else if u > 9, u <= 20 { y += 60 - (u - 9) / 11 * 60 }
        y -= 44 * exp(-pow((u - 88) / 26, 2))
    }
    return y
}

func drawECG(_ t: Double) {
    guard t > ecgStart, t < ecgEnd + 0.02 else { return }
    let head = headX(min(t, ecgEnd))
    let trail = 780 * CGFloat(1 - inCubic((t - 6.72) / 0.48))
    let tail = max(-60, head - trail)
    let colour = mixColor(C.pulse, C.cited, clamp((t - 6.85) / 0.35))
    if head - tail > 2 {
        let chunks = 24
        for k in 0..<chunks {
            let x0 = tail + (head - tail) * CGFloat(k) / CGFloat(chunks)
            let x1 = tail + (head - tail) * CGFloat(k + 1) / CGFloat(chunks)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x0, y: ecgY(x0)))
            var x = x0
            while x < x1 { x = min(x1, x + 2); path.addLine(to: CGPoint(x: x, y: ecgY(x))) }
            let fade = pow(Double(k + 1) / Double(chunks), 0.9)
            stroke(path, colour, width: 18, alpha: 0.14 * fade)
            stroke(path, colour, width: 5.5, alpha: fade)
        }
    }
    let at = CGPoint(x: head, y: ecgY(head))
    let r = mix(9, revealMark.dotR, clamp((t - 6.85) / 0.35))
    radial(at, 70, colour.copy(alpha: 0.45)!, colour.copy(alpha: 0)!)
    fill(circle(at, r), colour)
}

// MARK: Act one

func act1(_ t: Double) {
    guard t < 9.7 else { return }
    drawSheets(t)
    kinetic(lineIntro, baseline: 600, t: t, inAt: 0.15, outAt: 2.32, stagger: 0.07)
    drawCounter(t)
    kinetic(nobody, baseline: 900, t: t, inAt: 2.55, outAt: 3.48)
    kinetic(untilA, baseline: 850, t: t, inAt: 3.62, outAt: 4.5)
    kinetic(untilB, baseline: 1000, t: t, inAt: 3.74, outAt: 4.56)
    for (i, w) in events.enumerated() {
        let tin = ecgBeats[i]
        kinetic(w, baseline: 720, t: t, inAt: tin - 0.04, outAt: i < 3 ? ecgBeats[i + 1] - 0.1 : 6.9, stagger: 0.05)
    }
    drawECG(t)

    // The reveal. The dot is already there; the name slides out from behind it.
    guard t >= ecgEnd else { return }
    let leave = inCubic((t - 9.3) / 0.3)
    let settle = 1.07 - 0.07 * CGFloat(outCubic((t - 7.2) / 2.2))
    let swell = 1 + 0.5 * CGFloat(sin(.pi * clamp((t - 7.2) / 0.32)))
    group(alpha: 1 - leave, center: CGPoint(x: 540, y: 960), scale: settle, dy: -40 * CGFloat(leave)) {
        revealMark.draw(cx: 540, baseline: revealBase, p: (t - 7.26) / 0.85, dotScale: swell)
        kinetic(tagline, baseline: revealBase + 130, t: t, inAt: 7.95, stagger: 0.06)
    }
}

let tagline = Words("Your insurance, finally readable.", serif(58, .regular), C.secondary)
