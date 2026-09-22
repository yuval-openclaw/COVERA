import SwiftUI

/// The first screen after unlock, and the hub for everything else.
///
/// It answers one question — what do you need to do right now? — with one
/// main action and a few secondary ones. Nothing on it asserts anything about
/// cover; it only routes.
struct HomeView: View {
    let guidance: GuidanceModel
    let documents: DocumentsModel
    let callLog: CallLogStore
    let onOpenGuidance: () -> Void
    let onNewGuidance: () -> Void
    let onShowPolicies: () -> Void
    let onShowAccount: () -> Void

    @State private var importMethod: ImportMethod?
    @State private var selected: PolicyDocument?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCallLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section - 4) {
                    topRow.appearIn(0)
                    greeting.appearIn(1)
                    hero.appearIn(2)
                    quickActions.appearIn(3)
                    cover.appearIn(4)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.section)
            }
            .coveraScreen()
            .toolbar(.hidden, for: .navigationBar)
            .policyImport($importMethod, model: documents, onFinished: onShowPolicies)
            .sheet(isPresented: $showingCallLog) {
                CallLogView(store: callLog, onClose: { showingCallLog = false })
            }
            .sheet(item: $selected) { document in
                HomePolicySheet(document: document, onShowPolicies: {
                    selected = nil
                    onShowPolicies()
                })
            }
            .task { await documents.load() }
        }
    }

    // MARK: Sections

    private var topRow: some View {
        HStack {
            Wordmark(size: .title3)
            Spacer()
            Button(action: onShowAccount) {
                Image(systemName: "person.crop.circle")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(String(localized: "Account"))
        }
        .padding(.top, Theme.Spacing.tight)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Eyebrow(text: Date().formatted(.coveraDate.weekday(.wide).day().month(.wide)))
            Text(String(localized: "How can we help?"))
                .font(Theme.Typeface.display(.largeTitle))
                .tracking(AppLanguage.current.isLatinScript ? -0.4 : 0)
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let plan = guidance.plan {
            resumeCard(plan)
        } else {
            startCard
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            HStack(alignment: .top) {
                Image(systemName: "list.number")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.Palette.elevated, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                    .accessibilityHidden(true)
                Spacer()
                // Describes the questions, not the wait: how long the plan
                // takes to build depends on the documents, and we do not know.
                Text(String(localized: "A few taps"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Palette.tertiaryInk)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(String(localized: "Something happened?"))
                    .font(Theme.Typeface.display(.title))
                    .foregroundStyle(Theme.Palette.ink)
                Text(String(localized: "Answer a few one-tap questions and get a step-by-step plan drawn only from your own policies."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onNewGuidance) {
                HStack {
                    Text(String(localized: "Get a plan"))
                    Image(systemName: "arrow.forward")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.block + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coveraLuxury()
    }

    private func resumeCard(_ plan: GuidanceResponse) -> some View {
        let total = plan.steps.count
        let done = plan.steps.filter { guidance.completedSteps.contains($0.order) }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            // Side by side when it fits; stacked at large text sizes, where
            // squeezing them together hyphenates the eyebrow mid-word.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Eyebrow(text: String(localized: "Your current plan"))
                        .fixedSize()
                    Spacer()
                    progressLabel(done: done, total: total)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Eyebrow(text: String(localized: "Your current plan"))
                    progressLabel(done: done, total: total)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(guidance.kind?.title ?? String(localized: "Your plan"))
                    .font(Theme.Typeface.display(.title))
                    .foregroundStyle(Theme.Palette.ink)
                if let next = plan.steps.first(where: { !guidance.completedSteps.contains($0.order) }) {
                    // The next undone step, so the card answers "what now?"
                    // without opening anything.
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.tight) {
                        Text(String(localized: "Next"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.tertiaryInk)
                        Text(next.action)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.secondaryInk)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                }
            }

            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Theme.Palette.ink)

            HStack(spacing: Theme.Spacing.tight) {
                Button(action: onOpenGuidance) {
                    Text(String(localized: "Open plan"))
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onNewGuidance) {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(String(localized: "Start a new plan"))
            }
        }
        .padding(Theme.Spacing.block + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coveraLuxury()
    }

    private func progressLabel(done: Int, total: Int) -> some View {
        Text(String(localized: "\(done) of \(total) done"))
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(Theme.Palette.secondaryInk)
            .contentTransition(.numericText())
            .animation(Theme.Motion.pop, value: done)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            Eyebrow(text: String(localized: "Quick actions"))

            LazyVGrid(
                // One column at accessibility text sizes, so titles are never
                // cut to "Uploa…".
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.flexible())]
                    : [GridItem(.flexible(), spacing: Theme.Spacing.step), GridItem(.flexible(), spacing: Theme.Spacing.step)],
                spacing: Theme.Spacing.step
            ) {
                Menu {
                    Button {
                        importMethod = .pdf
                    } label: {
                        Label(String(localized: "Choose a file"), systemImage: "folder")
                    }
                    Button {
                        importMethod = .paste
                    } label: {
                        Label(String(localized: "Paste a copied PDF"), systemImage: "doc.on.clipboard")
                    }
                } label: {
                    ActionTileLabel(
                        icon: "doc.badge.plus",
                        title: String(localized: "Upload a PDF"),
                        subtitle: String(localized: "Choose or paste a file")
                    )
                }
                .buttonStyle(PressableStyle())
                .accessibilityElement(children: .combine)

                ActionTile(
                    icon: "doc.viewfinder",
                    title: String(localized: "Scan paper"),
                    subtitle: DocumentScanner.isAvailable
                        ? String(localized: "Use the camera")
                        : String(localized: "Needs a camera")
                ) { importMethod = .scan }
                    .disabled(!DocumentScanner.isAvailable)

                ActionTile(
                    icon: "doc.text",
                    title: String(localized: "Your policies"),
                    subtitle: documents.documents.isEmpty
                        ? String(localized: "None yet")
                        : String(localized: "\(documents.documents.count) stored")
                ) { onShowPolicies() }

                ActionTile(
                    icon: "phone.badge.waveform",
                    title: String(localized: "Call log"),
                    subtitle: callLog.entries.isEmpty
                        ? String(localized: "Record a call")
                        : String(localized: "\(callLog.entries.count) recorded")
                ) { showingCallLog = true }

                ActionTile(
                    icon: "lock.shield",
                    title: String(localized: "Your data"),
                    subtitle: String(localized: "Export or delete")
                ) { onShowAccount() }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            HStack {
                Eyebrow(text: String(localized: "Your cover"))
                Spacer()
                if !documents.documents.isEmpty {
                    Button(String(localized: "See all"), action: onShowPolicies)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .frame(minHeight: 44)
                }
            }

            if documents.documents.isEmpty {
                Button {
                    importMethod = .pdf
                } label: {
                    HStack(spacing: Theme.Spacing.step + 2) {
                        IconTile(systemName: "plus", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Add your first policy"))
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(String(localized: "The full wording your insurer sent you."))
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.tertiaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    )
                }
                .buttonStyle(PressableStyle())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.step) {
                        ForEach(Array(documents.documents.enumerated()), id: \.element.id) { position, document in
                            Button {
                                selected = document
                            } label: {
                                PolicyCard(document: document, height: 176, sheenDelay: Double(position) * 0.6)
                                    .frame(width: 290)
                            }
                            .buttonStyle(PressableStyle())
                            .appearIn(position + 4)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, Theme.Spacing.screen, for: .scrollContent)
                .padding(.horizontal, -Theme.Spacing.screen)
            }
        }
    }
}

/// A square quick action on the Home grid.
private struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ActionTileLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct ActionTileLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                IconTile(systemName: icon, tint: Theme.Palette.ink, size: 40)
                Spacer(minLength: Theme.Spacing.block)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .padding(.top, 2)
            }
            .padding(Theme.Spacing.block - 4)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A quick look at one policy from the Home carousel, with a way on to the
/// full library.
private struct HomePolicySheet: View {
    let document: PolicyDocument
    let onShowPolicies: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            PolicyCard(document: document, height: 190)
            Text(document.isReady
                 ? String(localized: "Every figure Covera quotes from this policy links back to its page.")
                 : document.statusDescription)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onShowPolicies) {
                Text(String(localized: "Open in Policies"))
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.block)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.background)
        .presentationCornerRadius(Theme.Radius.luxury + 6)
        .coveraLayoutDirection()
    }
}

#if DEBUG
#Preview {
    HomeView(
        guidance: PreviewData.guidanceModel(),
        documents: DocumentsModel(sample: PreviewData.documents),
        callLog: CallLogStore(sample: PreviewData.callLog),
        onOpenGuidance: {},
        onNewGuidance: {},
        onShowPolicies: {},
        onShowAccount: {}
    )
    .preferredColorScheme(.dark)
}
#endif
