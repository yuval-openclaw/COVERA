import SwiftUI

/// The first screen. Required by App Review (1.4.1 / 5.1.1) for a medical-adjacent
/// app, and required by honesty regardless: someone about to hand over their
/// health insurance file should know exactly what this is before they do.
///
/// There is no "skip", and no single button that carries all four points at
/// once. Each is confirmed on its own, so nobody arrives at a policy library
/// having agreed to something they scrolled past — the same shape as the
/// agreements recorded after sign-in (`ConsentView`).
struct OnboardingDisclaimerView: View {
    let onAccept: () -> Void

    @State private var confirmed = [false, false, false, false]

    private var allConfirmed: Bool { confirmed.allSatisfy { $0 } }

    private let points: [(icon: String, title: String, body: String)] = [
        (
            "doc.text.magnifyingglass",
            String(localized: "It reads your documents back to you"),
            String(localized: "Every figure it shows — a percentage, a cap, a deadline — is quoted from a page of your own policy, with the page number attached. If your policy does not say something, Covera says so and tells you what to ask your insurer.")
        ),
        (
            "stethoscope",
            String(localized: "It is not medical advice"),
            String(localized: "Covera is not a doctor. It will not tell you whether to have a procedure, and it does not know your medical history.")
        ),
        (
            "building.columns",
            String(localized: "It is not a licensed insurance agent"),
            String(localized: "Covera cannot approve or deny anything. Your insurer decides what is covered. Where the wording is ambiguous, you see both readings rather than a guess.")
        ),
        (
            "lock",
            String(localized: "Your documents stay yours"),
            String(localized: "Encrypted, kept to your account alone, and never used to train a model. Export or delete everything at any time from Account.")
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                Wordmark(size: .title2)
                    .padding(.top, Theme.Spacing.block)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(String(localized: "Before you start"))
                        .font(Theme.Typeface.display(.largeTitle))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityAddTraits(.isHeader)

                    Text(String(localized: "Four things to know about what Covera is — and what it is not. Confirm each one to continue."))
                        .font(.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Spacing.section)

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    row(index: index, icon: point.icon, title: point.title, body: point.body)
                        .appearIn(index + 2)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen + 4)
            .padding(.bottom, Theme.Spacing.section)
        }
        .coveraScreen()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // A short fade so rows scroll under the button instead of
                // being cut off by a hard edge.
                LinearGradient(
                    colors: [Theme.Palette.background.opacity(0), Theme.Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)

                // "Continue" would let someone say later that they were only
                // moving through a screen. Each point above is confirmed on its
                // own; this says what the four together mean. The agreements
                // recorded against an account still come after sign-in.
                Button(action: onAccept) {
                    Text(String(localized: "I agree"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!allConfirmed)
                .opacity(allConfirmed ? 1 : 0.45)
                .padding(.horizontal, Theme.Spacing.screen + 4)
                .padding(.bottom, Theme.Spacing.tight)
                .background(Theme.Palette.background)
                .accessibilityHint(Text(verbatim: allConfirmed ? "" : String(localized: "Confirm all four to continue")))
            }
        }
    }

    private func row(index: Int, icon: String, title: String, body: String) -> some View {
        let isOn = $confirmed[index]
        // The switch shares a row with the icon rather than the text: beside a
        // heading it squeezes it into three lines, and these points have to be
        // easy to read or confirming them means nothing.
        return VStack(alignment: .leading, spacing: Theme.Spacing.tight - 2) {
            HStack(spacing: Theme.Spacing.block - 4) {
                IconTile(systemName: icon, tint: Theme.Palette.cited, size: 40)
                Spacer(minLength: Theme.Spacing.step)
                // The point itself is the switch's label: hidden on screen,
                // since it is already beside it, and read aloud by VoiceOver.
                Toggle(isOn: isOn.animation(Theme.Motion.press)) { Text(verbatim: "\(title). \(body)") }
                    .labelsHidden()
                    .tint(Theme.Palette.cited)
            }
            .padding(.bottom, Theme.Spacing.tight - 4)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole point is what is being confirmed, so it is a target too.
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.Motion.press) { isOn.wrappedValue.toggle() } }
        .coveraCard()
    }
}

#if DEBUG
#Preview {
    OnboardingDisclaimerView(onAccept: {})
        .preferredColorScheme(.dark)
}
#endif
