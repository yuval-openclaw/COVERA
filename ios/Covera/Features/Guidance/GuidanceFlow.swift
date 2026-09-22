import SwiftUI

// MARK: - Intake vocabulary

/// The handful of situations the intake offers. Each only opens the sentence
/// sent to the server — none of them asserts anything about cover.
enum SituationKind: String, CaseIterable, Identifiable {
    case surgery, pregnancy, emergency, specialist, dental, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surgery: String(localized: "Planned surgery")
        case .pregnancy: String(localized: "Pregnancy and birth")
        case .emergency: String(localized: "Emergency")
        case .specialist: String(localized: "Specialist or tests")
        case .dental: String(localized: "Dental")
        case .other: String(localized: "Something else")
        }
    }

    var subtitle: String {
        switch self {
        case .surgery: String(localized: "An operation that is booked or being planned")
        case .pregnancy: String(localized: "Check-ups, tests and the birth itself")
        case .emergency: String(localized: "It is happening now, or just happened")
        case .specialist: String(localized: "A consultant, a scan, blood work")
        case .dental: String(localized: "Treatment, surgery or orthodontics")
        case .other: String(localized: "Describe it in your own words")
        }
    }

    var icon: String {
        switch self {
        case .surgery: "cross.case"
        case .pregnancy: "figure.and.child.holdinghands"
        case .emergency: "staroflife"
        case .specialist: "stethoscope"
        case .dental: "mouth"
        case .other: "ellipsis"
        }
    }

    /// First words of the situation sent to the server.
    var lead: String {
        switch self {
        case .surgery: String(localized: "Planned surgery.")
        case .pregnancy: String(localized: "Pregnancy and birth.")
        case .emergency: String(localized: "An emergency.")
        case .specialist: String(localized: "A specialist visit or tests.")
        case .dental: String(localized: "Dental treatment.")
        case .other: ""
        }
    }

    var detailsPlaceholder: String {
        switch self {
        case .surgery: String(localized: "Which operation, which hospital, and has a surgeon been chosen?")
        case .pregnancy: String(localized: "How far along, and is anything being monitored closely?")
        case .emergency: String(localized: "What happened, and where is the person being treated?")
        case .specialist: String(localized: "Which specialist or test, and who asked for it?")
        case .dental: String(localized: "What treatment has the dentist suggested?")
        case .other: String(localized: "What is happening, and who is it for?")
        }
    }
}

enum Recipient: String, CaseIterable, Identifiable {
    case me, partner, child, parent, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .me: String(localized: "Me")
        case .partner: String(localized: "My partner")
        case .child: String(localized: "My child")
        case .parent: String(localized: "My parent")
        case .other: String(localized: "Someone else")
        }
    }

    var icon: String {
        switch self {
        case .me: "person"
        case .partner: "person.2"
        case .child: "figure.child"
        case .parent: "figure.stand"
        case .other: "person.3"
        }
    }
}

enum Timing: String, CaseIterable, Identifiable {
    case now, days, weeks, unscheduled
    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: String(localized: "Right now")
        case .days: String(localized: "Within days")
        case .weeks: String(localized: "Within weeks")
        case .unscheduled: String(localized: "No date yet")
        }
    }

    var icon: String {
        switch self {
        case .now: "bolt"
        case .days: "clock"
        case .weeks: "calendar"
        case .unscheduled: "hourglass"
        }
    }
}

enum Referral: String, CaseIterable, Identifiable {
    case yes, no, unsure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .yes: String(localized: "Yes, I have one")
        case .no: String(localized: "No")
        case .unsure: String(localized: "Not sure")
        }
    }

    var icon: String {
        switch self {
        case .yes: "doc.text"
        case .no: "minus"
        case .unsure: "questionmark"
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class GuidanceModel {
    // Intake answers, one tap each.
    var kind: SituationKind?
    var details = ""
    var recipient: Recipient?
    var timing: Timing?
    var referral: Referral?

    /// Answers to the clarifying questions the server asked, keyed by question.
    var answers: [String: String] = [:]

    /// What was actually sent, for the recap on the plan.
    private(set) var situation = ""
    private(set) var plan: GuidanceResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The request failed only because no account is connected yet.
    private(set) var needsConnection = false
    /// Steps the reader has marked done. Kept in memory only, like the plan
    /// itself: plans are never cached, because a cached figure is one nobody
    /// re-verified.
    private(set) var completedSteps: Set<Int> = []

    init() {}

    var composedSituation: String {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return [kind?.lead ?? "", trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The intake taps, phrased as the answers the server would otherwise have
    /// to ask for. Sending them up front saves a round trip at the worst time.
    var intakeAnswers: [String: String] {
        var result: [String: String] = [:]
        if let recipient { result[String(localized: "Who is this for?")] = recipient.title }
        if let timing { result[String(localized: "How soon is it?")] = timing.title }
        if let referral { result[String(localized: "Is there already a referral?")] = referral.title }
        return result
    }

    var canSubmit: Bool { composedSituation.count >= 3 && !isLoading }

    func ask() async {
        let text = composedSituation
        guard text.count >= 3 else { return }

        situation = text
        isLoading = true
        errorMessage = nil
        needsConnection = false
        defer { isLoading = false }

        do {
            let clarified = answers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            let merged = intakeAnswers.merging(clarified) { _, typed in typed }
            plan = try await APIClient.shared.guidance(situation: text, answers: merged)
            completedSteps = []
        } catch {
            // The previous plan is cleared rather than left on screen: a stale
            // plan next to a fresh error is the kind of thing someone acts on.
            plan = nil
            if case APIError.notConfigured = error { needsConnection = true }
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleStep(_ order: Int) {
        if completedSteps.contains(order) {
            completedSteps.remove(order)
        } else {
            completedSteps.insert(order)
        }
    }

    func reset() {
        kind = nil
        details = ""
        recipient = nil
        timing = nil
        referral = nil
        answers = [:]
        situation = ""
        plan = nil
        errorMessage = nil
        needsConnection = false
        completedSteps = []
    }

    #if DEBUG
    /// Sample state for previews and the `-CoveraDemo` launch argument only.
    init(
        sampleKind kind: SituationKind,
        details: String,
        recipient: Recipient?,
        timing: Timing?,
        referral: Referral?,
        plan: GuidanceResponse,
        completed: Set<Int> = []
    ) {
        self.kind = kind
        self.details = details
        self.recipient = recipient
        self.timing = timing
        self.referral = referral
        self.plan = plan
        self.completedSteps = completed
        self.situation = [kind.lead, details].joined(separator: " ")
    }
    #endif
}

// MARK: - Flow

/// Guidance as a single focused flow, presented over everything else: a few
/// one-tap questions, a calm wait, then the plan.
struct GuidanceFlowView: View {
    @Bindable var model: GuidanceModel
    let onClose: () -> Void
    let onOpenAccount: () -> Void
    @State private var stepIndex = 0
    @State private var movingForward = true

    var body: some View {
        ZStack {
            if model.isLoading {
                ReadingView()
                    .transition(.opacity)
            } else if let plan = model.plan {
                PlanView(model: model, plan: plan, onClose: onClose, onNewPlan: startOver)
                    .transition(Theme.Motion.arrive)
            } else {
                IntakeView(
                    model: model,
                    stepIndex: $stepIndex,
                    movingForward: $movingForward,
                    onClose: onClose,
                    onOpenAccount: onOpenAccount
                )
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.appear, value: model.isLoading)
        .animation(Theme.Motion.appear, value: model.plan == nil)
        .sensoryFeedback(.impact(weight: .light), trigger: model.plan == nil)
    }

    private func startOver() {
        withAnimation(Theme.Motion.appear) {
            model.reset()
            stepIndex = 0
            movingForward = false
        }
    }
}

// MARK: - Intake

private enum IntakeQuestion: Hashable {
    case kind, details, recipient, timing, referral
}

private struct IntakeView: View {
    @Bindable var model: GuidanceModel
    @Binding var stepIndex: Int
    @Binding var movingForward: Bool
    let onClose: () -> Void
    let onOpenAccount: () -> Void

    @State private var advancing = false
    @FocusState private var detailsFocused: Bool

    private var questions: [IntakeQuestion] {
        var list: [IntakeQuestion] = [.kind, .details, .recipient]
        // In an emergency "how soon" has already been answered.
        if model.kind != .emergency { list.append(.timing) }
        list.append(.referral)
        return list
    }

    private var index: Int { min(stepIndex, questions.count - 1) }
    private var current: IntakeQuestion { questions[index] }
    private var isLast: Bool { index == questions.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block + 4) {
                    if model.kind == .emergency {
                        EmergencyCallCard()
                            .transition(Theme.Motion.arrive)
                    }

                    question(current)
                        .id(current)
                        .transition(movingForward ? Theme.Motion.advance : Theme.Motion.retreat)

                    if let error = model.errorMessage {
                        errorCard(error)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.block)
                .padding(.bottom, Theme.Spacing.section)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .coveraScreen()
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.step) {
            Button {
                goBack()
            } label: {
                Image(systemName: index == 0 ? "xmark" : "chevron.backward")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(index == 0 ? String(localized: "Close") : String(localized: "Back"))

            StepProgress(current: index, total: questions.count)

            Text(verbatim: "\(index + 1)/\(questions.count)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.Palette.tertiaryInk)
                .frame(minWidth: 30, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.tight)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.tight) {
            switch current {
            case .kind:
                EmptyView()
            case .details:
                Button {
                    advance()
                } label: {
                    Text(String(localized: "Continue"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSubmit)

                if model.kind != .other {
                    Text(String(localized: "Optional — but a little detail makes the plan sharper."))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.tertiaryInk)
                }
            case .recipient, .timing, .referral:
                Button {
                    advance()
                } label: {
                    Text(isLast ? String(localized: "Skip and build my plan") : String(localized: "Skip this question"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, Theme.Spacing.tight)
    }

    // MARK: Questions

    @ViewBuilder
    private func question(_ question: IntakeQuestion) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.block + 4) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title(question))
                    .font(Theme.Typeface.display(.largeTitle))
                    .tracking(AppLanguage.current.isLatinScript ? -0.4 : 0)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(question))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch question {
            case .kind:
                options(SituationKind.allCases, selected: model.kind, icon: \.icon, title: \.title, subtitle: \.subtitle) { kind in
                    model.kind = kind
                    if kind == .emergency { model.timing = .now }
                }
            case .details:
                detailsEditor
            case .recipient:
                options(Recipient.allCases, selected: model.recipient, icon: \.icon, title: \.title) { model.recipient = $0 }
            case .timing:
                options(Timing.allCases, selected: model.timing, icon: \.icon, title: \.title) { model.timing = $0 }
            case .referral:
                options(Referral.allCases, selected: model.referral, icon: \.icon, title: \.title) { model.referral = $0 }
            }
        }
    }

    private func options<Option: Identifiable & Equatable>(
        _ all: [Option],
        selected: Option?,
        icon: KeyPath<Option, String>,
        title: KeyPath<Option, String>,
        subtitle: KeyPath<Option, String>? = nil,
        apply: @escaping (Option) -> Void
    ) -> some View {
        VStack(spacing: Theme.Spacing.tight + 2) {
            ForEach(Array(all.enumerated()), id: \.element.id) { position, option in
                ChoiceRow(
                    icon: option[keyPath: icon],
                    title: option[keyPath: title],
                    subtitle: subtitle.map { option[keyPath: $0] },
                    isSelected: selected == option
                ) {
                    choose { apply(option) }
                }
                .appearIn(position)
            }
        }
    }

    private var detailsEditor: some View {
        ZStack(alignment: .topLeading) {
            if model.details.isEmpty {
                Text(model.kind?.detailsPlaceholder ?? SituationKind.other.detailsPlaceholder)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .padding(.horizontal, Theme.Spacing.step + 4)
                    .padding(.vertical, Theme.Spacing.step + 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $model.details)
                .font(.body)
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .focused($detailsFocused)
                .padding(Theme.Spacing.tight + 2)
                .frame(minHeight: 170)
                .accessibilityLabel(String(localized: "Details"))
        }
        .coveraInset()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                .strokeBorder(
                    detailsFocused ? Theme.Palette.ink.opacity(0.35) : Theme.Palette.hairline,
                    lineWidth: detailsFocused ? 1 : 0.5
                )
        )
        .onAppear { detailsFocused = true }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            NoticeCard(
                icon: "exclamationmark.triangle",
                tint: Theme.Palette.caution,
                title: String(localized: "No plan yet"),
                message: message
            )
            if model.needsConnection {
                Button {
                    onOpenAccount()
                } label: {
                    Label(String(localized: "Sign in again"), systemImage: "person.crop.circle")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            } else {
                Button {
                    Task { await model.ask() }
                } label: {
                    Label(String(localized: "Try again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .disabled(!model.canSubmit)
            }
        }
    }

    // MARK: Navigation

    private func title(_ question: IntakeQuestion) -> String {
        switch question {
        case .kind: String(localized: "What’s happening?")
        case .details: String(localized: "Tell us a little more")
        case .recipient: String(localized: "Who is it for?")
        case .timing: String(localized: "How soon is it?")
        case .referral: String(localized: "Do you have a referral?")
        }
    }

    private func subtitle(_ question: IntakeQuestion) -> String {
        switch question {
        case .kind: String(localized: "Choose the closest match. You can add detail next.")
        case .details: String(localized: "Write it the way you would say it to a friend.")
        case .recipient: String(localized: "Each person can be on a different policy.")
        case .timing: String(localized: "Some steps have to happen before treatment.")
        case .referral: String(localized: "From a family doctor or a specialist, if your policy asks for one.")
        }
    }

    /// Record the tap, let the selection register for a moment, then move on.
    private func choose(_ apply: () -> Void) {
        guard !advancing else { return }
        apply()
        advancing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            advancing = false
            advance()
        }
    }

    private func advance() {
        detailsFocused = false
        if isLast {
            Task { await model.ask() }
            return
        }
        movingForward = true
        withAnimation(Theme.Motion.appear) { stepIndex = index + 1 }
    }

    private func goBack() {
        detailsFocused = false
        guard index > 0 else {
            onClose()
            return
        }
        movingForward = false
        withAnimation(Theme.Motion.appear) { stepIndex = index - 1 }
    }
}

// MARK: - Waiting

private struct ReadingView: View {
    @State private var spinning = false
    @State private var breathing = false

    var body: some View {
        VStack(spacing: Theme.Spacing.block + 4) {
            Spacer()

            ReadingIllustration()
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.tight) {
                Text(String(localized: "Reading your policies"))
                    .font(Theme.Typeface.display(.title))
                    .foregroundStyle(Theme.Palette.ink)
                    .shimmer()
                Text(String(localized: "Every figure is checked against the page it came from before you see it."))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.section + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coveraScreen()
        .accessibilityElement(children: .combine)
        .onAppear {
            spinning = true
            breathing = true
        }
    }
}

/// A policy page being read: its lines light up one after another while a soft
/// scan beam passes over it. It shows what is actually happening — the
/// document is being read line by line — rather than an abstract spinner.
private struct ReadingIllustration: View {
    @State private var scanning = false
    private let lines: [CGFloat] = [1, 0.72, 0.9, 0.6, 0.84, 0.5]
    private let lineLength: CGFloat = 86

    var body: some View {
        let still = Theme.Motion.reduceMotion
        ZStack {
            Circle()
                .fill(Theme.Palette.cited.opacity(0.14))
                .frame(width: 210, height: 210)
                .blur(radius: 45)
                .scaleEffect(scanning && !still ? 1.08 : 0.94)
                .animation(still ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: scanning)

            VStack(alignment: .leading, spacing: 10) {
                Capsule()
                    .fill(Theme.Palette.ink.opacity(0.85))
                    .frame(width: 48, height: 7)
                    .padding(.bottom, 6)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, width in
                    Capsule()
                        .fill(Theme.Palette.secondaryInk.opacity(0.22))
                        .frame(width: lineLength * width, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.Palette.cited)
                                .frame(width: scanning || still ? lineLength * width : 0, height: 5)
                                .animation(
                                    still ? nil : .easeInOut(duration: 0.7)
                                        .delay(Double(index) * 0.3)
                                        .repeatForever(autoreverses: true),
                                    value: scanning
                                )
                        }
                }
            }
            .padding(20)
            .frame(width: 130, height: 168, alignment: .topLeading)
            .coveraLuxury(radius: 20)
            .overlay {
                if !still {
                    ZStack {
                        LinearGradient(
                            colors: [.clear, Theme.Palette.cited.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 46)
                        Rectangle()
                            .fill(Theme.Palette.cited.opacity(0.9))
                            .frame(height: 1.5)
                            .shadow(color: Theme.Palette.cited, radius: 6)
                    }
                    .offset(y: scanning ? 84 : -84)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: scanning)
                    // Sized to the whole page before clipping, so the beam
                    // sweeps the full sheet instead of a clipped sliver.
                    .frame(width: 130, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .frame(width: 220, height: 220)
        .onAppear { scanning = true }
    }
}

#if DEBUG
#Preview("Intake") {
    GuidanceFlowView(model: GuidanceModel(), onClose: {}, onOpenAccount: {})
        .preferredColorScheme(.dark)
}

#Preview("Plan") {
    GuidanceFlowView(model: PreviewData.guidanceModel(), onClose: {}, onOpenAccount: {})
        .preferredColorScheme(.dark)
}
#endif
