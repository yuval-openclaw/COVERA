import SwiftUI

/// The first screen. Required by App Review (1.4.1 / 5.1.1) for a medical-adjacent
/// app, and required by honesty regardless: someone about to hand over their
/// health insurance file should know exactly what this is before they do.
///
/// There is no "skip". The accept button is the only way forward.
struct OnboardingDisclaimerView: View {
    let onAccept: () -> Void

    /// Explicit consent, off until the user turns it on. Health information is
    /// special-category data (GDPR Art. 9) and consumer health data under US
    /// state law; both need an affirmative act, not a pre-ticked box.
    @State private var agreed = false

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
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(size: .title2)
                    .padding(.top, Theme.Spacing.block)

                Text(String(localized: "Before you start"))
                    .font(Theme.Typeface.display(.largeTitle))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, Theme.Spacing.section + 12)
                    .accessibilityAddTraits(.isHeader)

                Text(String(localized: "Four things to know about what Covera is — and what it is not."))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.tight)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        row(number: index + 1, icon: point.icon, title: point.title, body: point.body)
                            .appearIn(index + 2)
                        if index < points.count - 1 {
                            Rectangle()
                                .fill(Theme.Palette.hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.section)
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

                VStack(alignment: .leading, spacing: Theme.Spacing.step) {
                    Toggle(isOn: $agreed.animation(Theme.Motion.press)) {
                        Text(String(localized: "I am 18 or older, and I agree that Covera may process the health information in my documents as described in the Privacy Policy."))
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            // The sentence is the thing being agreed to, so it
                            // is a target too, not only the small switch.
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(Theme.Motion.press) { agreed.toggle() } }
                    }
                    .tint(Theme.Palette.cited)

                    HStack(spacing: Theme.Spacing.block) {
                        Link(String(localized: "Privacy Policy"), destination: Legal.privacy)
                        Link(String(localized: "Terms of Use"), destination: Legal.terms)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.cited)

                    Button(action: onAccept) {
                        Text(String(localized: "Agree and continue"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!agreed)
                    .opacity(agreed ? 1 : 0.45)
                }
                .padding(.horizontal, Theme.Spacing.screen + 4)
                .padding(.bottom, Theme.Spacing.tight)
                .background(Theme.Palette.background)
            }
        }
    }

    private func row(number: Int, icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.block - 4) {
            IconTile(systemName: icon, tint: Theme.Palette.cited, size: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight - 2) {
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
        }
        .padding(.vertical, Theme.Spacing.block)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    OnboardingDisclaimerView(onAccept: {})
        .preferredColorScheme(.dark)
}
#endif
