import SwiftUI

/// Google's "G", drawn to their spec.
///
/// Their brand guidelines require the real mark on a sign-in button — a letter
/// "G" in a circle, which is what this app used before, is not it, and using a
/// substitute is both off-brand and the sort of thing App Review notices.
/// Four arcs, four brand colours, from Google's published 48×48 artwork.
///
/// `Path` rather than an image asset so it stays sharp at any size and needs
/// no binary in the asset catalogue.
struct GoogleLogo: View {
    var size: CGFloat = 20

    // The published artwork is drawn in a 48×48 box; every point below is in
    // that space and scaled at draw time.
    private static let box: CGFloat = 48

    var body: some View {
        Canvas { context, _ in
            let scale = size / Self.box
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for segment in Self.segments {
                context.fill(segment.path.applying(transform), with: .color(segment.colour))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct Segment {
        let colour: Color
        let path: Path
    }

    private static let segments: [Segment] = [
        // Blue — the horizontal bar and the right edge.
        Segment(colour: Color(red: 0.259, green: 0.522, blue: 0.957), path: Path { p in
            p.move(to: CGPoint(x: 45.12, y: 24.5))
            p.addCurve(to: CGPoint(x: 44.72, y: 20), control1: CGPoint(x: 45.12, y: 22.94), control2: CGPoint(x: 44.98, y: 21.44))
            p.addLine(to: CGPoint(x: 24, y: 20))
            p.addLine(to: CGPoint(x: 24, y: 28.51))
            p.addLine(to: CGPoint(x: 35.84, y: 28.51))
            p.addCurve(to: CGPoint(x: 31.45, y: 35.15), control1: CGPoint(x: 35.33, y: 31.26), control2: CGPoint(x: 33.78, y: 33.59))
            p.addLine(to: CGPoint(x: 31.45, y: 40.67))
            p.addLine(to: CGPoint(x: 38.56, y: 40.67))
            p.addCurve(to: CGPoint(x: 45.12, y: 24.5), control1: CGPoint(x: 42.72, y: 36.84), control2: CGPoint(x: 45.12, y: 31.2))
            p.closeSubpath()
        }),
        // Green — the lower arc.
        Segment(colour: Color(red: 0.204, green: 0.659, blue: 0.325), path: Path { p in
            p.move(to: CGPoint(x: 24, y: 46))
            p.addCurve(to: CGPoint(x: 38.56, y: 40.67), control1: CGPoint(x: 29.94, y: 46), control2: CGPoint(x: 34.92, y: 44.03))
            p.addLine(to: CGPoint(x: 31.45, y: 35.15))
            p.addCurve(to: CGPoint(x: 24, y: 37.25), control1: CGPoint(x: 29.48, y: 36.47), control2: CGPoint(x: 26.96, y: 37.25))
            p.addCurve(to: CGPoint(x: 11.69, y: 28.18), control1: CGPoint(x: 18.27, y: 37.25), control2: CGPoint(x: 13.42, y: 33.38))
            p.addLine(to: CGPoint(x: 4.34, y: 28.18))
            p.addLine(to: CGPoint(x: 4.34, y: 33.88))
            p.addCurve(to: CGPoint(x: 24, y: 46), control1: CGPoint(x: 7.96, y: 41.07), control2: CGPoint(x: 15.4, y: 46))
            p.closeSubpath()
        }),
        // Yellow — the left arc.
        Segment(colour: Color(red: 0.984, green: 0.737, blue: 0.020), path: Path { p in
            p.move(to: CGPoint(x: 11.69, y: 28.18))
            p.addCurve(to: CGPoint(x: 11, y: 24), control1: CGPoint(x: 11.25, y: 26.86), control2: CGPoint(x: 11, y: 25.45))
            p.addCurve(to: CGPoint(x: 11.69, y: 19.82), control1: CGPoint(x: 11, y: 22.55), control2: CGPoint(x: 11.25, y: 21.14))
            p.addLine(to: CGPoint(x: 11.69, y: 14.12))
            p.addLine(to: CGPoint(x: 4.34, y: 14.12))
            p.addCurve(to: CGPoint(x: 2, y: 24), control1: CGPoint(x: 2.85, y: 17.09), control2: CGPoint(x: 2, y: 20.45))
            p.addCurve(to: CGPoint(x: 4.34, y: 33.88), control1: CGPoint(x: 2, y: 27.55), control2: CGPoint(x: 2.85, y: 30.91))
            p.addLine(to: CGPoint(x: 11.69, y: 28.18))
            p.closeSubpath()
        }),
        // Red — the upper arc.
        Segment(colour: Color(red: 0.918, green: 0.263, blue: 0.208), path: Path { p in
            p.move(to: CGPoint(x: 24, y: 10.75))
            p.addCurve(to: CGPoint(x: 32.41, y: 14.04), control1: CGPoint(x: 27.23, y: 10.75), control2: CGPoint(x: 30.13, y: 11.86))
            p.addLine(to: CGPoint(x: 38.72, y: 7.73))
            p.addCurve(to: CGPoint(x: 24, y: 2), control1: CGPoint(x: 34.91, y: 4.18), control2: CGPoint(x: 29.93, y: 2))
            p.addCurve(to: CGPoint(x: 4.34, y: 14.12), control1: CGPoint(x: 15.4, y: 2), control2: CGPoint(x: 7.96, y: 6.93))
            p.addLine(to: CGPoint(x: 11.69, y: 19.82))
            p.addCurve(to: CGPoint(x: 24, y: 10.75), control1: CGPoint(x: 13.42, y: 14.62), control2: CGPoint(x: 18.27, y: 10.75))
            p.closeSubpath()
        }),
    ]
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        GoogleLogo(size: 20)
        GoogleLogo(size: 44)
    }
    .padding(40)
    .background(Color.black)
}
#endif

/// Google's dark sign-in button surface: a near-black fill with a light hairline,
/// which is what their dark theme specifies, and a capsule so it pairs with the
/// Sign in with Apple button above it.
struct GoogleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Theme.Palette.inset : Theme.Palette.elevated,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
