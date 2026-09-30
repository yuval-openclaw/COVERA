import AppKit

// Act three, 16.8–24.0 s: honesty, the plan, the chat.
//  16.80  "Not in your policy?" — an amber card; 18.0 "Covera says so."
//  19.20  "When something happens, a plan, step by step." — four steps on the beat
//  21.60  "Ask anything." — question, typing, cited answer; 23.35 "Every answer shows its page."
// Colours keep their meaning from the app: blue cited, amber not stated, coral deadline.

let notIn = Words("Not in your policy?", fitted("Not in your policy?", 104) { serif($0, .medium) }, C.ink)
let saysSo = Words("Covera says so.", fitted("Covera says so.", 104) { serif($0, .medium) }, C.ink)
let whenA = Words("When something happens,", fitted("When something happens,", 88) { serif($0, .medium) }, C.ink)
let whenB = Words("a plan, step by step.", fitted("a plan, step by step.", 88) { serif($0, .medium) }, C.ink)
let askHead = Words("Ask anything.", fitted("Ask anything.", 124) { serif($0, .medium) }, C.ink)
let askSub = Words("Every answer shows its page.", serif(58, .regular), C.secondary)

let notStatedCard = CGRect(x: 90, y: 520, width: 900, height: 560)
let notStatedText = paragraph("Your policy doesn’t say whether you need a referral.", serif(46, .regular), C.ink, width: 788, spacing: 10)
let notStatedAsk = paragraph("“Do I need a referral from my family doctor?”", serif(40, .regular, italic: true), C.ink, width: 788, spacing: 8)

func drawNotStated(_ t: Double) {
    guard t > 17.1, t < 19.4 else { return }
    let pop = spring(t, 17.2, k: 9, f: 12)
    let leave = inCubic((t - 18.98) / 0.3)
    let r = notStatedCard
    group(alpha: min(1, pop * 1.8) * (1 - leave), center: CGPoint(x: r.midX, y: r.midY), scale: CGFloat(0.86 + 0.14 * pop),
          dx: -1250 * CGFloat(leave)) {
        drawCard(r, border: C.amber.copy(alpha: 0.22))
        let x = r.minX + 56, y = r.minY
        func stage(_ at: Double) -> (Double, CGFloat) { let p = outCubic((t - at) / 0.4); return (p, 18 * CGFloat(1 - p)) }
        var (a, dy) = stage(17.25)
        _ = chip("Not stated in your policy", color: C.amber, at: CGPoint(x: x, y: y + 56 + dy), dot: true, alpha: a)
        (a, dy) = stage(17.35)
        drawImage(notStatedText.image, CGRect(x: x, y: y + 150 + dy, width: 788, height: notStatedText.size.height), alpha: a)
        fill(CGPath(rect: CGRect(x: x, y: y + 330, width: 788, height: 2), transform: nil), C.rule, alpha: a)
        (a, dy) = stage(17.55)
        drawText(text("ASK YOUR INSURER", sans(24, .semibold), C.tertiary, kern: 3), x: x, baseline: y + 396 + dy, alpha: a)
        (a, dy) = stage(17.65)
        drawImage(notStatedAsk.image, CGRect(x: x, y: y + 420 + dy, width: 788, height: notStatedAsk.size.height), alpha: a)
    }
}

// MARK: The plan

struct Step { let title: String; let chips: [(String, CGColor)]; let note: String? }

let steps = [
    Step(title: "Ask the Fund for prior approval", chips: [("Page 7", C.cited)], note: nil),
    Step(title: "Check if you need a referral", chips: [("Ask your insurer", C.amber)], note: nil),
    Step(title: "Keep the itemised invoice", chips: [], note: "and the surgeon’s operative report"),
    Step(title: "Submit the claim", chips: [("Within 90 days", C.coral), ("Page 12", C.cited)], note: nil),
]

func drawPlan(_ t: Double) {
    guard t > 19.6, t < 21.8 else { return }
    for (i, s) in steps.enumerated() {
        let at = 19.8 + Double(i) * 0.3
        let p = spring(t, at, k: 9, f: 12)
        let leave = inCubic((t - 21.4 - Double(i) * 0.03) / 0.25)
        guard p > 0 else { continue }
        let r = CGRect(x: 90, y: 560 + CGFloat(i) * 222, width: 900, height: 190)
        group(alpha: min(1, p * 1.8) * (1 - leave), dx: 520 * CGFloat(1 - p) - 1250 * CGFloat(leave)) {
            drawCard(r)
            let c = CGPoint(x: r.minX + 76, y: r.midY)
            fill(circle(c, 36), C.ink)
            let n = text("\(i + 1)", sans(34, .semibold), C.paper)
            drawText(n, x: c.x - n.width / 2, baseline: c.y + (n.ascent - n.descent) / 2)
            drawText(text(s.title, sans(38, .semibold), C.ink), x: r.minX + 142, baseline: r.minY + 82)
            var x = r.minX + 142
            for (j, (label, colour)) in s.chips.enumerated() {
                let q = spring(t, at + 0.12 + Double(j) * 0.08, k: 10, f: 14)
                x += chip(label, color: colour, at: CGPoint(x: x, y: r.minY + 108), size: 27, alpha: min(1, q * 2)) + 12
            }
            if let note = s.note {
                drawText(text(note, sans(30), C.tertiary), x: x, baseline: r.minY + 142)
            }
        }
    }
}

// MARK: The chat

let question = paragraph("How long do I have to submit a claim?", sans(40), C.paper, width: 560, spacing: 6)
let answer = paragraph("Within 90 days of the operation.", sans(40), C.ink, width: 620, spacing: 6)

func drawChat(_ t: Double) {
    guard t > 21.9, t < 24.1 else { return }
    let leave = inCubic((t - 23.84) / 0.24)
    group(alpha: 1 - leave, dy: -80 * CGFloat(leave)) {
        // The question, from the right.
        let qp = spring(t, 21.95, k: 9, f: 12)
        let qr = CGRect(x: 990 - question.size.width - 72, y: 540, width: question.size.width + 72, height: question.size.height + 56)
        group(alpha: min(1, qp * 2), center: CGPoint(x: qr.maxX, y: qr.maxY), scale: CGFloat(0.7 + 0.3 * qp), dx: 160 * CGFloat(1 - qp)) {
            drawCard(qr, radius: 44, fill: C.ink, shadow: 0.18)
            drawImage(question.image, CGRect(x: qr.minX + 36, y: qr.minY + 28, width: question.size.width, height: question.size.height))
        }
        // Typing, then the answer, from the left.
        let ay = qr.maxY + 48
        let typing = clamp((t - 22.25) / 0.1) * (1 - clamp((t - 22.56) / 0.08))
        if typing > 0 {
            let tr = CGRect(x: 90, y: ay, width: 170, height: 100)
            group(alpha: typing) {
                drawCard(tr, radius: 44)
                for k in 0..<3 {
                    let phase = sin((t - 22.25) * 12 - Double(k) * 0.9)
                    fill(circle(CGPoint(x: tr.minX + 52 + CGFloat(k) * 33, y: tr.midY - 5 * CGFloat(max(0, phase))), 9),
                         C.tertiary, alpha: 0.45 + 0.4 * max(0, phase))
                }
            }
        }
        let ap = spring(t, 22.62, k: 9, f: 12)
        if ap > 0 {
            let ar = CGRect(x: 90, y: ay, width: answer.size.width + 72, height: answer.size.height + 56 + 68)
            group(alpha: min(1, ap * 2), center: CGPoint(x: ar.minX, y: ar.maxY), scale: CGFloat(0.7 + 0.3 * ap)) {
                drawCard(ar, radius: 44)
                drawImage(answer.image, CGRect(x: ar.minX + 36, y: ar.minY + 28, width: answer.size.width, height: answer.size.height))
                let cp = spring(t, 22.98, k: 10, f: 14)
                _ = chip("Page 12 · §21", color: C.cited, at: CGPoint(x: ar.minX + 36, y: ar.minY + answer.size.height + 40),
                         size: 28, alpha: min(1, cp * 2))
            }
        }
    }
}

func act3(_ t: Double) {
    guard t > 16.7, t < 24.2 else { return }
    kinetic(notIn, baseline: 330, t: t, inAt: 16.86, outAt: 19.0)
    drawNotStated(t)
    kinetic(saysSo, baseline: 1340, t: t, inAt: 18.0, outAt: 19.02)
    let underline = outCubic((t - 18.3) / 0.35) * (1 - clamp((t - 19.0) / 0.15))
    if underline > 0 {
        let x0 = 540 - saysSo.width / 2 + saysSo.xs[1]
        let w = (saysSo.width - saysSo.xs[1]) * CGFloat(underline)
        fill(rounded(CGRect(x: x0, y: 1340 + 26, width: w, height: 8), 4), C.amber, alpha: 0.85)
    }
    kinetic(whenA, baseline: 250, t: t, inAt: 19.26, outAt: 21.4)
    kinetic(whenB, baseline: 360, t: t, inAt: 19.38, outAt: 21.44)
    drawPlan(t)
    kinetic(askHead, baseline: 330, t: t, inAt: 21.66, outAt: 23.84)
    drawChat(t)
    kinetic(askSub, baseline: 1110, t: t, inAt: 22.95, outAt: 23.86, stagger: 0.05)
}
