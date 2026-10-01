import SwiftUI

/// The plan: an ordered list where every figure is traceable to a page of the
/// reader's own policy.
///
/// Three rules govern the layout:
///   1. A number never appears without its basis badge next to it.
///   2. What the policy does not say is shown at the same visual weight as what
///      it does. A gap is information, not an empty state.
///   3. Nothing is styled as success. No green, no ticks, no "Approved".
///      A step the reader has done inverts its number; it is their progress,
///      not the insurer's verdict.
struct PlanView: View {
    @Bindable var model: GuidanceModel
    let plan: GuidanceResponse
    let onClose: () -> Void
    let onNewPlan: () -> Void

    @State private var sheet: PlanSheet?

    private var insurerPhone: String? {
        plan.steps.lazy.compactMap { step -> String? in
            if case let .notStated(_, phone) = step.basis { return phone }
            return nil
        }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                header.appearIn(0)

                if model.kind == .emergency {
                    EmergencyCallCard().appearIn(1)
                }

                summaryCard.appearIn(1)

                DisclaimerBanner(text: plan.disclaimer).appearIn(2)

                if plan.includesTranscribedPages {
                    NoticeCard(
                        icon: "text.viewfinder",
                        tint: Theme.Palette.unstated,
                        title: String(localized: "Some of this came from a scan"),
                        message: String(localized: "Part of the evidence was read from a scanned page by transcribing it. Confirm anything decisive against the paper document.")
                    )
                    .appearIn(3)
                }

                if !plan.withheld.isEmpty {
                    withheldCard.appearIn(4)
                }

                if !plan.clarifyingQuestions.isEmpty {
                    clarifyingCard(plan.clarifyingQuestions).appearIn(5)
                }

                if !plan.steps.isEmpty {
                    stepsCard.appearIn(6)
                }

                if !plan.conflicts.isEmpty {
                    conflictsCard.appearIn(7)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, 60)
            .padding(.bottom, Theme.Spacing.section)
        }
        .coveraScreen()
        // A deeper blur than other screens, so text scrolling under the
        // floating buttons fades out instead of colliding with them.
        .overlay(alignment: .top) { TopEdgeBlur(depth: 72) }
        .overlay(alignment: .top) { topBar }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(item: $sheet) { sheet in
            TextSheet(sheet: sheet)
        }
    }

    // MARK: Chrome

    /// Floating, so closing is always one tap away however far down you are.
    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(String(localized: "Close"))

            Spacer()

            Button(action: onNewPlan) {
                Label(String(localized: "New plan"), systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.tight)
    }

    @ViewBuilder
    private var actionBar: some View {
        let actions = barActions
        if !actions.isEmpty {
            HStack(spacing: Theme.Spacing.tight) {
                ForEach(actions) { action in
                    if let url = action.url {
                        Link(destination: url) { ActionBarLabel(action: action) }
                            .buttonStyle(PressableStyle())
                    } else if let sheet = action.sheet {
                        Button { self.sheet = sheet } label: { ActionBarLabel(action: action) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(Theme.Spacing.tight)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.tight)
        }
    }

    private var barActions: [BarAction] {
        var actions: [BarAction] = []
        if let phone = insurerPhone,
           let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
            actions.append(BarAction(id: "call", icon: "phone.fill", title: String(localized: "Call insurer"), url: url, sheet: nil))
        }
        if let script = plan.phoneScript {
            actions.append(BarAction(id: "script", icon: "text.bubble", title: String(localized: "Call script"), url: nil, sheet: .script(script)))
        }
        if let email = plan.draftClaimEmail {
            actions.append(BarAction(id: "email", icon: "envelope", title: String(localized: "Claim email"), url: nil, sheet: .email(email)))
        }
        return actions
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Eyebrow(text: String(localized: "Your plan"))

            Text(model.kind?.title ?? String(localized: "Your plan"))
                .font(Theme.Typeface.display(.largeTitle))
                .tracking(AppLanguage.current.isLatinScript ? -0.4 : 0)
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)

            let details = model.details.trimmingCharacters(in: .whitespacesAndNewlines)
            if !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .lineLimit(3)
            }

            let chips = metaChips
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.tight) {
                        ForEach(chips, id: \.text) { chip in
                            MetaChip(text: chip.text, systemImage: chip.icon)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var metaChips: [(text: String, icon: String)] {
        var chips: [(String, String)] = []
        if let recipient = model.recipient { chips.append((String(localized: "For: \(recipient.title)"), recipient.icon)) }
        if let timing = model.timing { chips.append((timing.title, timing.icon)) }
        if let referral = model.referral { chips.append((String(localized: "Referral: \(referral.title)"), "doc.text")) }
        return chips
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Eyebrow(text: String(localized: "Summary"))
            Text(plan.summary)
                .font(Theme.Typeface.display(.title3))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.block + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coveraLuxury()
    }

    private var withheldCard: some View {
        // Deliberately prominent. A withheld step is the system working, and
        // the reader needs to know a gap exists rather than assume the plan is
        // complete.
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Label(String(localized: "Some steps were held back"), systemImage: "eye.slash")
                .font(.headline)
                .foregroundStyle(Theme.Palette.caution)
            Text(String(localized: "Clausa drafted these but could not trace them to your documents, so it will not show them. Ask your insurer instead."))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(plan.withheld, id: \.self) { reason in
                BulletedLine(text: reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryInk)
            }
        }
        .coveraCard(accent: Theme.Palette.caution)
    }

    private var stepsCard: some View {
        let total = plan.steps.count
        let done = plan.steps.filter { model.completedSteps.contains($0.order) }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: String(localized: "What to do"))
                    Spacer()
                    Text(String(localized: "\(done) of \(total) done"))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .contentTransition(.numericText())
                        .animation(Theme.Motion.pop, value: done)
                }
                // Neutral ink, not green: this measures the reader's progress
                // through a list, not anything the insurer has agreed to.
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(Theme.Palette.ink)
                    .animation(Theme.Motion.appear, value: done)
                Text(String(localized: "Tap a number to mark that step done."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.steps) { step in
                    StepRow(
                        step: step,
                        isLast: step.id == plan.steps.last?.id,
                        isDone: model.completedSteps.contains(step.order),
                        onToggle: {
                            withAnimation(Theme.Motion.expand) { model.toggleStep(step.order) }
                        }
                    )
                }
            }
        }
        .coveraCard()
        .sensoryFeedback(.selection, trigger: done)
    }

    private var conflictsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Label(String(localized: "Your policies do not agree"), systemImage: "arrow.triangle.branch")
                .font(.headline)
                .foregroundStyle(Theme.Palette.caution)
            Text(String(localized: "Clausa does not choose between these. Your insurer decides which applies."))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(plan.conflicts, id: \.self) { conflict in
                BulletedLine(text: conflict)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .coveraCard(accent: Theme.Palette.caution)
    }

    private func clarifyingCard(_ questions: [ClarifyingQuestion]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                Eyebrow(text: String(localized: "Would change this plan"), tint: Theme.Palette.cited)
                Text(String(localized: "A few quick answers make the plan more precise."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
            }
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(question.question)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(question.why)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(
                        String(localized: "Your answer"),
                        text: Binding(
                            get: { model.answers[question.question] ?? "" },
                            set: { model.answers[question.question] = $0 }
                        )
                    )
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, Theme.Spacing.step + 2)
                    .frame(minHeight: 46)
                    .coveraInset()
                }
                .accessibilityElement(children: .contain)
            }
            Button(String(localized: "Update the plan")) {
                Task { await model.ask() }
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.Palette.cited, fullWidth: true))
            .disabled(model.isLoading)
        }
        .coveraCard(accent: Theme.Palette.cited)
    }
}

// MARK: - Action bar

private struct BarAction: Identifiable {
    let id: String
    let icon: String
    let title: String
    let url: URL?
    let sheet: PlanSheet?
}

private struct ActionBarLabel: View {
    let action: BarAction

    var body: some View {
        VStack(spacing: 4) {
            // Fixed icon height, so labels line up however tall each symbol is.
            Image(systemName: action.icon)
                .font(.system(size: 17, weight: .medium))
                .frame(height: 22)
            Text(action.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Theme.Palette.elevated.opacity(0.7), in: Capsule())
    }
}

enum PlanSheet: Identifiable {
    case script(String)
    case email(String)

    var id: String {
        switch self {
        case .script: "script"
        case .email: "email"
        }
    }
}

private struct TextSheet: View {
    let sheet: PlanSheet
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private var content: (icon: String, title: String, note: String, text: String) {
        switch sheet {
        case let .script(text):
            ("text.bubble", String(localized: "If you call them"), String(localized: "Read this out. It asks only what your documents leave open."), text)
        case let .email(text):
            ("envelope", String(localized: "Draft claim email"), String(localized: "Check it before sending. Nothing is sent for you."), text)
        }
    }

    var body: some View {
        let content = content
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                HStack(spacing: Theme.Spacing.step) {
                    IconTile(systemName: content.icon, tint: Theme.Palette.cited, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(Theme.Typeface.display(.title2))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(content.note)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(content.text)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coveraInset()
            }
            .padding(Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.tight)
        }
        // Pinned, so the two things you came to do are visible at any sheet
        // height without scrolling.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Theme.Spacing.tight) {
                Button {
                    UIPasteboard.general.string = content.text
                    withAnimation(Theme.Motion.expand) { copied = true }
                } label: {
                    // No tick: a checkmark in this app should never be
                    // confused with an approval.
                    Label(
                        copied ? String(localized: "Copied") : String(localized: "Copy"),
                        systemImage: copied ? "doc.on.doc.fill" : "doc.on.doc"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))

                ShareLink(item: content.text) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
            .sensoryFeedback(.selection, trigger: copied)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.step)
            .background(Theme.Palette.surface)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.surface)
        .presentationCornerRadius(Theme.Radius.luxury + 6)
        .coveraLayoutDirection()
    }
}

// MARK: - Step

/// One step on the timeline. The badge and the citation are part of the step,
/// not a footnote — you cannot read the instruction without seeing where it
/// came from.
private struct StepRow: View {
    let step: ActionStep
    let isLast: Bool
    let isDone: Bool
    let onToggle: () -> Void
    @State private var showingQuote = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.tight) {
            // Node and rail. The rail stretches to the height of the content
            // because the row is fixed to its ideal height below.
            VStack(spacing: 0) {
                Button(action: onToggle) {
                    Text("\(step.order)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isDone ? Theme.Palette.background : Theme.Palette.ink)
                        .frame(width: 32, height: 32)
                        .background(isDone ? Theme.Palette.ink : Theme.Palette.elevated, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                        // A small spring on the reader's own progress.
                        .scaleEffect(isDone ? 1.07 : 1)
                        .animation(Theme.Motion.pop, value: isDone)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(isDone
                    ? String(localized: "Step \(step.order), done. Tap to mark as not done.")
                    : String(localized: "Mark step \(step.order) as done"))

                if !isLast {
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.tight + 2) {
                Text(step.action)
                    .font(.body)
                    .foregroundStyle(isDone ? Theme.Palette.secondaryInk : Theme.Palette.ink)
                    .animation(Theme.Motion.expand, value: isDone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                if let deadline = step.deadlineNote {
                    Pill(text: deadline, systemImage: "clock", tint: Theme.Palette.caution)
                }

                if case let .cited(citation) = step.basis {
                    citedDetail(citation)
                } else {
                    BasisBadge(basis: step.basis)
                    basisDetail
                }
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.section - 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    /// Badge and page reference on one line, so they read as a single
    /// citation; they wrap onto two only when the text size demands it.
    private func citedDetail(_ citation: SourceCitation) -> some View {
        let pageToggle = Button {
            withAnimation(Theme.Motion.expand) { showingQuote.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.hair + 2) {
                Text(citation.clauseRef.map { String(localized: "Page \(citation.page) · \($0)") }
                     ?? String(localized: "Page \(citation.page)"))
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .rotationEffect(.degrees(showingQuote ? 180 : 0))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Palette.cited)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingQuote
            ? String(localized: "Hide the quoted wording from page \(citation.page)")
            : String(localized: "Show the quoted wording from page \(citation.page)"))

        return VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.step) {
                    BasisBadge(basis: step.basis)
                    pageToggle
                }
                VStack(alignment: .leading, spacing: 0) {
                    BasisBadge(basis: step.basis)
                    pageToggle
                }
            }

            if showingQuote {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("“\(citation.verbatimQuote)”")
                        .font(Theme.Typeface.quote)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Word for word from your policy, page \(citation.page)."))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.tertiaryInk)
                }
                .padding(Theme.Spacing.step + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coveraInset()
                .overlay(alignment: .leading) {
                    Theme.Palette.cited
                        .frame(width: 2)
                        .padding(.vertical, Theme.Spacing.step)
                }
                .transition(Theme.Motion.unfold)
            }
        }
    }

    /// Detail for steps without a citation. Cited steps use `citedDetail`.
    @ViewBuilder
    private var basisDetail: some View {
        switch step.basis {
        case .cited, .general:
            EmptyView()

        case let .notStated(ask, phone):
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(String(localized: "Ask your insurer"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.unstated)
                Text(ask)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let phone, let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) {
                        Label(String(localized: "Call \(phone)"), systemImage: "phone.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.Palette.unstated))
                    .padding(.top, Theme.Spacing.hair)
                }
            }
            .padding(Theme.Spacing.step + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Palette.unstated.opacity(0.08),
                in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
            )
        }
    }
}
