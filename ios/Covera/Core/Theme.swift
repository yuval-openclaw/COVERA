import SwiftUI
import UIKit

/// The visual language.
///
/// Black, deliberately. Covera is opened at night in a hospital corridor as
/// often as at a desk, and a true-black OLED ground is the calmest thing a
/// phone can show. The register is quiet luxury — a private bank's letter, not
/// a fintech dashboard: serif headlines, generous spacing, fine lit edges, and
/// a faint ambient glow instead of colour.
///
/// Colour carries meaning and nothing else:
///   blue   — this came from your policy (a citation)
///   amber  — your policy does not say; ask your insurer
///   coral  — a deadline, a conflict, or something withheld
/// There is no green anywhere and no checkmark. Nothing here has been approved
/// by an insurer, and a green tick would say otherwise.
enum Theme {
    /// Which ground the app is drawn on. **This is the only line to change to
    /// swap the whole app back to the original black.** Every colour, the
    /// metal surface, the lit edges and the status bar follow it.
    enum Appearance { case light, dark }
    static let appearance: Appearance = .light

    private static var isLight: Bool { appearance == .light }

    enum Palette {
        /// The ground everything sits on: warm paper, not white, so the screen
        /// reads as something printed rather than something clinical.
        static var background: Color { Theme.isLight ? Color(hex: 0xF7F2EC) : Color(hex: 0x000000) }
        /// Cards, lifted off the ground by being warmer and lighter than it.
        static var surface: Color { Theme.isLight ? Color(hex: 0xFFFCF8) : Color(hex: 0x0E0E11) }
        /// Inputs, quotes, anything set into a card.
        static var inset: Color { Theme.isLight ? Color(hex: 0xF1EAE1) : Color(hex: 0x18181D) }
        /// Chips, pressed states, icon tiles.
        static var elevated: Color { Theme.isLight ? Color(hex: 0xE9E0D5) : Color(hex: 0x222228) }
        static var hairline: Color {
            Theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.09)
        }
        /// The faint light behind each screen. Never used for meaning — it is
        /// warmth, which is the whole difference between calm and clinical.
        static var ambient: Color { Theme.isLight ? Color(hex: 0xFBE3D2) : Color(hex: 0x1C2233) }
        /// Highlights on a lifted surface: light catching metal in the dark,
        /// and a soft shadow on paper in the light.
        static var sheen: Color { Theme.isLight ? Color.black : Color.white }

        // Every text colour below clears WCAG AA (4.5:1) on `surface` *and* on
        // `background`, in both appearances.
        static var ink: Color { Theme.isLight ? Color(hex: 0x1C1B20) : Color(hex: 0xF4F4F6) }
        static var secondaryInk: Color { Theme.isLight ? Color(hex: 0x5A5860) : Color(hex: 0xA3A3AA) }
        static var tertiaryInk: Color { Theme.isLight ? Color(hex: 0x6A6872) : Color(hex: 0x7F7F87) }

        /// Citations and anything the documents actually support.
        static var cited: Color { Theme.isLight ? Color(hex: 0x2A5BD7) : Color(hex: 0x93B4FF) }
        /// Where the documents are silent. Not red: a gap is not an error, it
        /// is a question for the insurer.
        static var unstated: Color { Theme.isLight ? Color(hex: 0x8A5A05) : Color(hex: 0xF0B65A) }
        /// Deadlines, conflicts and withheld steps only.
        static var caution: Color { Theme.isLight ? Color(hex: 0xC03A2B) : Color(hex: 0xFF8B7B) }
    }

    enum Spacing {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let step: CGFloat = 12
        static let block: CGFloat = 20
        static let section: CGFloat = 32
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 22
        static let luxury: CGFloat = 26
        static let inset: CGFloat = 14
        static let tile: CGFloat = 12
    }

    enum Typeface {
        /// Serif display face (New York). Used for headings only.
        static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
            .system(style, design: .serif)
        }

        /// Verbatim policy wording. Serif italic reads as quoted, not narrated.
        static let quote = Font.system(.callout, design: .serif).italic()
    }

    /// One place to change motion. Everything is short and eases out; nothing
    /// bounces, springs or draws attention to itself.
    ///
    /// All of it respects Reduce Motion. Someone who has turned that on has
    /// usually turned it on for a reason — vestibular sensitivity, migraine —
    /// and this app is read while unwell.
    @MainActor
    enum Motion {
        static var appear: Animation? { reduceMotion ? nil : .easeOut(duration: 0.24) }
        static var expand: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }
        static var press: Animation? { reduceMotion ? nil : .easeOut(duration: 0.14) }
        /// A small spring for something the reader just did — marking a step
        /// done, a count changing. Never for anything the insurer decided.
        static var pop: Animation? { reduceMotion ? nil : .bouncy(duration: 0.4, extraBounce: 0.1) }

        /// Content arriving or leaving a screen: rises slightly and softens.
        static var arrive: AnyTransition {
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        }

        /// A block opening inside a card, like a quote under its citation.
        static var unfold: AnyTransition {
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top))
        }

        /// Moving between questions: a short slide in reading direction, or a
        /// plain fade when motion is reduced.
        static var advance: AnyTransition {
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
        }

        static var retreat: AnyTransition {
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                )
        }

        static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Grounds

/// Black with a faint cool light falling from the top leading corner. It gives
/// the screen depth without a single element competing for attention.
struct AmbientBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.Palette.background
            RadialGradient(
                colors: [Theme.Palette.ambient, Theme.Palette.background.opacity(0)],
                center: UnitPoint(x: 0.1, y: -0.08),
                startRadius: 0,
                endRadius: 560
            )
            .scaleEffect(1.3)
            .offset(x: drift ? 26 : -22, y: drift ? 30 : -12)
            // A second, cooler pool low on the screen so the black is never flat.
            RadialGradient(
                colors: [Theme.Palette.cited.opacity(0.07), Theme.Palette.background.opacity(0)],
                center: UnitPoint(x: 0.95, y: 1.05),
                startRadius: 0,
                endRadius: 420
            )
            .scaleEffect(1.3)
            .offset(x: drift ? -18 : 14, y: drift ? -16 : 10)
        }
        // Very slow, barely perceptible: light moving in a room, not an
        // animation. Reduce Motion stops it entirely.
        .animation(
            Theme.Motion.reduceMotion ? nil : .easeInOut(duration: 16).repeatForever(autoreverses: true),
            value: drift
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { drift = true }
    }
}

/// Content settles in on first appearance — a short rise out of a blur,
/// staggered by position, so a screen assembles rather than snapping into
/// place. Skipped entirely under Reduce Motion.
struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .blur(radius: shown ? 0 : 3)
            .onAppear {
                guard !shown else { return }
                guard !Theme.Motion.reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(.smooth(duration: 0.5).delay(Double(index) * 0.07)) { shown = true }
            }
    }
}

extension View {
    func appearIn(_ index: Int) -> some View { modifier(AppearIn(index: index)) }
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// A slow highlight travelling across text while the app is working. Used only
/// where something is genuinely in progress, never as decoration.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Theme.Palette.ink.opacity(Theme.Motion.reduceMotion ? 0 : 0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: phase * proxy.size.width * 1.5)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !Theme.Motion.reduceMotion else { return }
                withAnimation(.linear(duration: 2.1).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

/// A blurred edge under the status bar, fading into the page, the way iOS's own
/// scroll edges behave. Screens draw their own serif headers instead of a
/// navigation bar, which also removes the bar's backdrop — without this,
/// scrolled text would run straight through the clock.
///
/// `depth` is how far below the safe-area edge the blur reaches; screens with
/// floating buttons at the top pass enough to sit behind them too.
struct TopEdgeBlur: View {
    var depth: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.safeAreaInsets.top
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: inset + depth)
                .offset(y: -inset)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// A raised card on the black ground: a surface fill and a hairline edge, no
/// shadow. An optional accent draws a thin bar on the leading edge — leading,
/// not left, so it follows the reading direction in Hebrew and Arabic.
struct CardModifier: ViewModifier {
    var accent: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        content
            .padding(Theme.Spacing.block)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: shape)
            .overlay(alignment: .leading) {
                if let accent {
                    accent
                        .frame(width: 3)
                        .padding(.vertical, Theme.Spacing.block)
                        .clipShape(Capsule())
                }
            }
            .overlay(shape.strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}

/// The premium surface: brushed dark metal with a lit edge, brighter where the
/// ambient light would catch it. Reserved for the few objects a screen is
/// about — the plan's summary, a policy, the main action.
struct LuxurySurface: ViewModifier {
    var radius: CGFloat = Theme.Radius.luxury

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: Theme.appearance == .light
                            ? [Color(hex: 0xFFFFFF), Color(hex: 0xFFFAF4), Color(hex: 0xF6EDE2)]
                            : [Color(hex: 0x1E1E24), Color(hex: 0x111114), Color(hex: 0x0B0B0D)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // The sheen: a soft diagonal band — light on anodised metal
                    // in the dark, and the same band as shadow on paper.
                    LinearGradient(
                        stops: [
                            .init(color: Theme.Palette.sheen.opacity(0.07), location: 0),
                            .init(color: Theme.Palette.sheen.opacity(0), location: 0.38),
                            .init(color: Theme.Palette.sheen.opacity(0.025), location: 0.72),
                            .init(color: Theme.Palette.sheen.opacity(0), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(shape)
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: Theme.appearance == .light
                            ? [Color.black.opacity(0.10), Color.black.opacity(0.04), Color.black.opacity(0.07)]
                            : [.white.opacity(0.24), .white.opacity(0.05), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            )
    }
}

extension View {
    func coveraCard(accent: Color? = nil) -> some View { modifier(CardModifier(accent: accent)) }

    func coveraLuxury(radius: CGFloat = Theme.Radius.luxury) -> some View {
        modifier(LuxurySurface(radius: radius))
    }

    /// A block set into a card: inputs, quotes, scripts.
    func coveraInset(radius: CGFloat = Theme.Radius.inset) -> some View {
        background(Theme.Palette.inset, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The black ground with ambient light, edge to edge, and a blurred edge
    /// under the status bar.
    func coveraScreen() -> some View {
        background(AmbientBackground())
            .overlay(alignment: .top) { TopEdgeBlur() }
    }
}

// MARK: - Type

/// Small uppercase label above a group. Tracks wide so it reads as structure,
/// not content.
struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.Palette.tertiaryInk

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(AppLanguage.current.isLatinScript ? 1.6 : 0)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The wordmark. Serif, with the accent full stop.
struct Wordmark: View {
    var size: Font.TextStyle = .title3

    var body: some View {
        let name = Text(verbatim: "Covera").foregroundStyle(Theme.Palette.ink)
        let stop = Text(verbatim: ".").foregroundStyle(Theme.Palette.cited)
        Text("\(name)\(stop)")
            .font(Theme.Typeface.display(size).weight(.semibold))
            // A name is never broken across lines ("Cov-era.").
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Covera")
    }
}

/// Top of every screen. Screens draw their own header instead of using the
/// navigation bar so the serif display face can carry the title.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.step) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(Theme.Typeface.display(.largeTitle))
                    .tracking(AppLanguage.current.isLatinScript ? -0.4 : 0)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, Theme.Spacing.step)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

// MARK: - Buttons

/// White on black. The one thing on a screen you are meant to press.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Palette.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Theme.Spacing.block)
            .background(Theme.Palette.ink, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.32)
            .scaleEffect(configuration.isPressed && !Theme.Motion.reduceMotion ? 0.985 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Quiet alternative: a dark capsule with a hairline edge.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.ink
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, Theme.Spacing.block)
            .background(
                configuration.isPressed ? Theme.Palette.inset : Theme.Palette.elevated,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

/// Round icon button, 44pt so it clears the minimum touch target.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .frame(width: 44, height: 44)
            .background(
                configuration.isPressed ? Theme.Palette.inset : Theme.Palette.elevated,
                in: Circle()
            )
            .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .contentShape(Circle())
    }
}

/// For whole cards and tiles that act as buttons: a slight settle on press so
/// the surface feels physical, and nothing else.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Theme.Motion.reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Small parts

/// A rounded square holding a symbol. Used as the leading element in rows.
struct IconTile: View {
    let systemName: String
    var tint: Color = Theme.Palette.ink
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Theme.Palette.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct Pill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).imageScale(.small)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A neutral fact about the situation ("For my child", "Within weeks"). Grey,
/// because it describes the question, not the policy.
struct MetaChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.Palette.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}

/// Thin segmented progress for multi-step flows.
struct StepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.Palette.ink : Theme.Palette.elevated)
                    .frame(height: 3)
            }
        }
        .animation(Theme.Motion.appear, value: current)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Question \(current + 1) of \(total)"))
    }
}

/// A large one-tap answer. Selecting is the whole interaction: the flow moves
/// on by itself, so a frightened reader never hunts for a Next button.
struct ChoiceRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.step + 2) {
                // Selected inverts to white-on-black: unmistakable at a glance,
                // and still not a tick.
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Palette.background : Theme.Palette.ink)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? Theme.Palette.ink : Theme.Palette.elevated,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(isSelected ? Theme.Palette.ink : Theme.Palette.hairline, lineWidth: isSelected ? 6 : 1)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.step + 2)
            .padding(.vertical, Theme.Spacing.step)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                isSelected ? Theme.Palette.elevated : Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card - 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card - 4, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.ink.opacity(0.5) : Theme.Palette.hairline, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// The standing disclaimer.
///
/// A view rather than a string constant so it cannot be rendered in a weight or
/// colour that hides it. On plans, the text comes from the server response so
/// client and server cannot disagree about what was promised.
struct DisclaimerBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.step) {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryInk)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.step + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A bullet point that survives right-to-left layout.
///
/// `"• " + text` puts the bullet on the wrong side in Hebrew and Arabic, which
/// this app must handle — Israeli supplementary policies are the first target
/// market. An HStack mirrors automatically; a concatenated string does not.
struct BulletedLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.tight) {
            Text(verbatim: "•").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Marks where a claim comes from. Every figure on screen sits next to one.
struct BasisBadge: View {
    let basis: StepBasis

    var body: some View {
        switch basis {
        case .cited:
            Pill(text: String(localized: "From your policy"), systemImage: "doc.text", tint: Theme.Palette.cited)
        case .notStated:
            Pill(text: String(localized: "Not stated — ask your insurer"), systemImage: "questionmark.circle", tint: Theme.Palette.unstated)
        case .general:
            Pill(text: String(localized: "General step"), systemImage: "list.bullet", tint: Theme.Palette.tertiaryInk)
        }
    }
}

/// A notice with a coloured leading edge.
struct NoticeCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .coveraCard(accent: tint)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ambient motion

/// A band of light that crosses a card every few seconds, like a reflection
/// moving over metal. Staggered by `delay` so a list never flashes in unison.
struct Sheen: ViewModifier {
    var delay: Double = 0
    @State private var sweep = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [.clear, Theme.Palette.sheen.opacity(0.09), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.4, height: proxy.size.height * 2)
                    .rotationEffect(.degrees(20))
                    .offset(x: sweep ? width * 1.2 : -width * 0.6, y: -proxy.size.height / 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.luxury, style: .continuous))
                .allowsHitTesting(false)
                .opacity(Theme.Motion.reduceMotion ? 0 : 1)
            }
            .onAppear {
                guard !Theme.Motion.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).delay(2.4 + delay).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

/// A gentle hover, for an empty state's single icon.
struct Float: ViewModifier {
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -5 : 5)
            .animation(Theme.Motion.reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

/// A status dot. It breathes only while something is actually in progress.
struct StatusDot: View {
    let tint: Color
    let pulsing: Bool
    @State private var on = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .background(
                Circle()
                    .fill(tint.opacity(0.35))
                    .scaleEffect(pulsing && on ? 2.6 : 1)
                    .opacity(pulsing && on ? 0 : 1)
            )
            .animation(pulsing && !Theme.Motion.reduceMotion ? .easeOut(duration: 1.4).repeatForever(autoreverses: false) : nil, value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}
