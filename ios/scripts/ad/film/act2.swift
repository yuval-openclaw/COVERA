import AppKit

// Act two, 9.6–16.8 s: how it works, on paper.
//   9.60  "Add your policy." — the document lands
//  10.72  "Clausa reads every page." — a scan passes over it
//  11.70  "48 pages · read and stored"
//  12.00  zoom into page 12; "Every figure, from your own policy."
//  12.90  the sentence is highlighted; 13.6 its figure lifts into a card
//  14.40  "Page 12 · §21", traced back to the sentence; 14.75 "With the page, and the exact words."
// The figure is the sample policy's own: page 12, §21 says claims are due within 90 days.

let addPolicy = Words("Add your policy.", fitted("Add your policy.", 108) { serif($0, .medium) }, C.ink)
let readsA = Words("Clausa reads", serif(108, .medium), C.ink)
let readsB = Words("every page.", serif(108, .medium), C.ink)
let figureA = Words("Every figure,", serif(98, .medium), C.ink)
let figureB = Words("from your own policy.", fitted("from your own policy.", 98) { serif($0, .medium) }, C.ink)
let pageA = Words("With the page,", serif(98, .medium), C.ink)
let pageB = Words("and the exact words.", fitted("and the exact words.", 98) { serif($0, .medium) }, C.ink)

// MARK: The document

let docRect = CGRect(x: 230, y: 560, width: 620, height: 820)

/// Placeholder lines of policy text: (y offset, width, is heading).
let docLines: [(CGFloat, CGFloat, Bool)] = {
    var r = Rand(s: 99)
    var out: [(CGFloat, CGFloat, Bool)] = []
    var y: CGFloat = 214, k = 0
    while y < 780 {
        let heading = k % 6 == 0
        out.append((y, heading ? r.range(180, 260) : (r.next() > 0.2 ? 524 : r.range(200, 420)), heading))
        y += heading ? 44 : 32
        k += 1
    }
    return out
}()

func drawDocument(_ t: Double) {
    let rise = CGFloat(1 - spring(t, 9.78))
    let zoom = inCubic((t - 11.95) / 0.35)
    guard t > 9.7, zoom < 1 else { return }
    group(alpha: 1 - zoom, center: CGPoint(x: 540, y: 900), scale: 1 + 0.7 * CGFloat(zoom), dy: rise * 1350) {
        for (dx, dy, rot) in [(-26.0, 14.0, -0.05), (24.0, 22.0, 0.045)] as [(CGFloat, CGFloat, CGFloat)] {
            group(center: CGPoint(x: docRect.midX, y: docRect.midY), dx: dx, dy: dy, rotate: rot) {
                drawCard(docRect, radius: 30, fill: rgb(0xF4EDE4), shadow: 0.1)
            }
        }
        drawCard(docRect, radius: 30)
        let x = docRect.minX, y = docRect.minY
        drawText(text("Supplementary Health", serif(40, .semibold), C.ink), x: x + 48, baseline: y + 96)
        drawText(text("Policy Wording 2026", sans(27), C.tertiary), x: x + 48, baseline: y + 140)
        fill(CGPath(rect: CGRect(x: x + 48, y: y + 172, width: 524, height: 2), transform: nil), C.rule)

        let scan = inOutCubic((t - 10.8) / 0.9)
        let beamY = y + 170 + CGFloat(scan) * 640
        for (ly, w, heading) in docLines {
            let read = t > 10.8 && y + ly < beamY
            let colour = read ? mixColor(heading ? rgb(0xCFC4B6) : C.rule, C.cited, heading ? 0.55 : 0.3)
                              : (heading ? rgb(0xCFC4B6) : C.rule)
            fill(rounded(CGRect(x: x + 48, y: y + ly, width: w, height: heading ? 16 : 12), 6), colour)
        }
        if t > 10.8, t < 11.75 {
            ctx.saveGState()
            ctx.addPath(rounded(docRect, 30)); ctx.clip()
            let g = CGGradient(colorsSpace: space, colors: [C.cited.copy(alpha: 0)!, C.cited.copy(alpha: 0.16)!] as CFArray,
                               locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: beamY - 150), end: CGPoint(x: 0, y: beamY), options: [])
            fill(CGPath(rect: CGRect(x: docRect.minX, y: beamY - 1.5, width: docRect.width, height: 3), transform: nil),
                 C.cited, alpha: 0.85 * sin(.pi * scan))
            ctx.restoreGState()
        }
    }
    // The result of the read, under the page.
    let pop = spring(t, 11.7, k: 9, f: 13)
    if pop > 0, zoom < 1 {
        let label = "48 pages · read and stored"
        let w = text(label, sans(30, .semibold), C.cited).width + 30 * 1.24 + 30 * 0.55
        group(alpha: min(1, pop * 2) * (1 - zoom), center: CGPoint(x: 540, y: 1452), scale: CGFloat(0.6 + 0.4 * pop)) {
            _ = chip(label, color: C.cited, at: CGPoint(x: 540 - w / 2, y: 1427), dot: true)
        }
    }
}

// MARK: Page 12, and the figure that comes off it

let excerpt = CGRect(x: 90, y: 480, width: 900, height: 470)
let result = CGRect(x: 90, y: 1050, width: 900, height: 560)
let sentence1 = text("A claim must be submitted within", serif(44, .regular), C.ink)
let sentence90 = text("90 days", serif(44, .regular), C.ink)
let sentence90Blue = text("90 days", serif(44, .regular), C.cited)  // same weight, so "of" keeps its space
let sentenceEnd = text(" of the operation.", serif(44, .regular), C.ink)
let bigFigure = text("90 days", serif(150, .medium), C.cited)
let quote = paragraph("“A claim must be submitted within 90 days of the operation.”", serif(31, .regular, italic: true),
                      C.secondary, width: 760, spacing: 8)

func drawCitation(_ t: Double) {
    guard t > 11.95, t < 16.9 else { return }
    let leave = inCubic((t - 16.5) / 0.32)
    let slide = -1250 * CGFloat(leave)

    // The page.
    let enter = outCubic((t - 12.0) / 0.45)
    group(alpha: enter * (1 - leave), center: CGPoint(x: 540, y: excerpt.midY), scale: 0.9 + 0.1 * CGFloat(enter), dx: slide) {
        drawCard(excerpt)
        let x = excerpt.minX + 56, y = excerpt.minY
        drawText(text("PAGE 12", sans(24, .semibold), C.tertiary, kern: 3), x: x, baseline: y + 78)
        let clause = text("§21 · Claims", serif(30, .regular), C.secondary)
        drawText(clause, x: excerpt.maxX - 56 - clause.width, baseline: y + 78)
        fill(CGPath(rect: CGRect(x: x, y: y + 104, width: 788, height: 2), transform: nil), C.rule)
        for (ly, w) in [(140.0, 788.0), (176.0, 690.0), (374.0, 760.0), (410.0, 520.0)] as [(CGFloat, CGFloat)] {
            fill(rounded(CGRect(x: x, y: y + ly, width: w, height: 12), 6), C.rule)
        }
        // The highlighter, across both lines of the sentence.
        let mark = clamp((t - 12.9) / 0.6)
        let line2W = sentence90.width + sentenceEnd.width
        let p1 = CGFloat(clamp(mark / 0.6)), p2 = CGFloat(clamp((mark - 0.6) / 0.4))
        if p1 > 0 { fill(rounded(CGRect(x: x - 8, y: y + 262 - 44, width: (sentence1.width + 16) * p1, height: 60), 8), C.cited, alpha: 0.13) }
        if p2 > 0 { fill(rounded(CGRect(x: x - 8, y: y + 322 - 44, width: (line2W + 16) * p2, height: 60), 8), C.cited, alpha: 0.13) }
        drawText(sentence1, x: x, baseline: y + 262)
        drawText(sentence90, x: x, baseline: y + 322, alpha: 1 - clamp((t - 13.6) / 0.2))
        drawText(sentence90Blue, x: x, baseline: y + 322, alpha: clamp((t - 13.6) / 0.2))
        drawText(sentenceEnd, x: x + sentence90.width, baseline: y + 322)
    }

    // The card the figure lands in.
    let cardIn = spring(t, 13.7, k: 9, f: 12)
    let cardDY = (1 - CGFloat(cardIn)) * 90
    let rx = result.minX + 56, ry = result.minY + cardDY
    if cardIn > 0 {
        group(alpha: min(1, cardIn * 1.6) * (1 - leave), dx: slide, dy: cardDY) {
            drawCard(result)
            let x = result.minX + 56, y = result.minY
            drawText(text("CLAIM DEADLINE", sans(24, .semibold), C.tertiary, kern: 3), x: x, baseline: y + 84)
            let sub = outCubic((t - 14.15) / 0.4)
            drawText(text("to submit your claim, after the operation", sans(34), C.secondary), x: x,
                     baseline: y + 316 + 20 * CGFloat(1 - sub), alpha: sub)
            let q = outCubic((t - 15.3) / 0.5)
            if q > 0 {
                fill(rounded(CGRect(x: x, y: y + 440, width: 5, height: quote.size.height - 12), 2.5), C.cited, alpha: q)
                drawImage(quote.image, CGRect(x: x + 28 + 16 * CGFloat(1 - q), y: y + 432, width: quote.size.width,
                                              height: quote.size.height), alpha: q)
            }
        }
    }
    // The chip, and the dotted line back to where the figure was read.
    let chipPop = spring(t, 14.4, k: 10, f: 14)
    if chipPop > 0 {
        let label = "Page 12 · §21"
        let chipW = text(label, sans(30, .semibold), C.cited).width + 30 * 1.24
        // A bracket down the left margin, from the chip back to the sentence,
        // so it never crosses the figure it is explaining.
        let trace = outCubic((t - 14.45) / 0.55)
        if trace > 0 {
            let points = [CGPoint(x: rx - 16, y: ry + 376), CGPoint(x: 50, y: ry + 376),
                          CGPoint(x: 50, y: excerpt.minY + 300), CGPoint(x: excerpt.minX + 40, y: excerpt.minY + 300)]
            group(alpha: 1 - leave, dx: slide) {
                stroke(trimmed(points, trace), C.cited, width: 4, alpha: 0.75, dash: [1, 12])
            }
        }
        group(alpha: min(1, chipPop * 2) * (1 - leave), center: CGPoint(x: rx + chipW / 2, y: ry + 376),
              scale: CGFloat(0.5 + 0.5 * chipPop), dx: slide) {
            _ = chip(label, color: C.cited, at: CGPoint(x: rx, y: ry + 350))
        }
    }

    // The figure itself: off the page, up, and into the card.
    let fly = inOutCubic((t - 13.6) / 0.55)
    if fly > 0 {
        let small: CGFloat = 44 / 150
        let startX = excerpt.minX + 56, startB = excerpt.minY + 322
        let endX = rx, endB = ry + 250
        let s = mix(small, 1, fly)
        let arc = -120 * CGFloat(sin(.pi * fly))
        group(alpha: 1 - leave, dx: slide) {
            drawText(bigFigure, x: mix(startX, endX, fly), baseline: mix(startB, endB, fly) + arc, scale: s)
        }
    }
}

func act2(_ t: Double) {
    guard t > 9.5, t < 17 else { return }
    kinetic(addPolicy, baseline: 340, t: t, inAt: 9.66, outAt: 10.58)
    kinetic(readsA, baseline: 280, t: t, inAt: 10.72, outAt: 11.88)
    kinetic(readsB, baseline: 400, t: t, inAt: 10.8, outAt: 11.92)
    drawDocument(t)
    kinetic(figureA, baseline: 250, t: t, inAt: 12.05, outAt: 14.55)
    kinetic(figureB, baseline: 365, t: t, inAt: 12.2, outAt: 14.6)
    kinetic(pageA, baseline: 250, t: t, inAt: 14.95, outAt: 16.48)
    kinetic(pageB, baseline: 365, t: t, inAt: 15.05, outAt: 16.52)
    drawCitation(t)
}
