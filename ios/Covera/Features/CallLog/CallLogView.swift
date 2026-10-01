import SwiftUI

/// Every contact with an insurer, in the user's own words.
///
/// Presented as a sheet rather than a tab: it belongs to a claim in progress,
/// and it is reached from Home and from a policy.
struct CallLogView: View {
    let store: CallLogStore
    /// When set, the log is filtered to one policy and new entries attach to it.
    var documentID: String?
    var policyName: String?
    let onClose: () -> Void

    @State private var editing: CallLogEntry?
    @State private var pendingDeletion: CallLogEntry?

    private var rows: [CallLogEntry] { store.entries(for: documentID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    ScreenHeader(
                        eyebrow: String(localized: "Your record"),
                        title: String(localized: "Call log"),
                        subtitle: policyName ?? String(localized: "Every contact with your insurer, in your own words.")
                    ) {
                        Button {
                            editing = CallLogEntry(documentID: documentID, policyName: policyName)
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .frame(width: 44, height: 44)
                                .background(Theme.Palette.elevated, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                        }
                        .accessibilityLabel(String(localized: "Add a contact"))
                    }

                    if let problem = store.problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if rows.isEmpty {
                        emptyState.appearIn(1)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, entry in
                            Button {
                                editing = entry
                            } label: {
                                CallLogCard(entry: entry, showPolicy: documentID == nil)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeletion = entry
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                            .appearIn(position + 1)
                        }
                        .animation(Theme.Motion.appear, value: rows.count)

                        ShareLink(item: store.transcript(for: documentID)) {
                            Label(String(localized: "Share the record"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .appearIn(rows.count + 1)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.section)
            }
            .coveraScreen()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(String(localized: "Done"), action: onClose)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryInk)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.tight)
            }
            .sheet(item: $editing) { entry in
                CallLogEditor(
                    entry: entry,
                    onSave: {
                        store.save($0)
                        editing = nil
                    },
                    onCancel: { editing = nil }
                )
                .coveraLayoutDirection()
            }
            .alert(
                String(localized: "Delete this contact?"),
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
            ) {
                Button(String(localized: "Cancel"), role: .cancel) { pendingDeletion = nil }
                Button(String(localized: "Delete"), role: .destructive) {
                    if let pendingDeletion { store.delete(pendingDeletion) }
                    pendingDeletion = nil
                }
            } message: {
                Text(String(localized: "This note is only on this device, so it cannot be recovered."))
            }
        }
        .coveraLayoutDirection()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.step) {
            IconTile(systemName: "phone.badge.waveform", tint: Theme.Palette.ink, size: 44)

            Text(String(localized: "Nothing recorded yet"))
                .font(Theme.Typeface.display(.title3))
                .foregroundStyle(Theme.Palette.ink)

            Text(String(localized: "After each call, write down the date, who you spoke to and the reference number they gave you. If the insurer later says something different, this is what settles it."))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                editing = CallLogEntry(documentID: documentID, policyName: policyName)
            } label: {
                Label(String(localized: "Add the first one"), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Theme.Spacing.tight)
        }
        .padding(Theme.Spacing.block + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coveraLuxury()
    }
}

/// One contact, at a glance: when, who, and the reference that proves it.
private struct CallLogCard: View {
    let entry: CallLogEntry
    let showPolicy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.tight) {
                Label(entry.kind.label, systemImage: entry.kind.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryInk)
                Spacer()
                Text(entry.date.formatted(.coveraDate.day().month().year().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
            }

            if !entry.person.isEmpty {
                Text(entry.person)
                    .font(Theme.Typeface.display(.title3))
                    .foregroundStyle(Theme.Palette.ink)
            }

            if !entry.reference.isEmpty {
                // The reference number is the single most useful thing here, so
                // it is the one figure the card highlights.
                MetaChip(text: entry.reference, systemImage: "number")
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !entry.sent.isEmpty {
                Label(entry.sent, systemImage: "paperclip")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .lineLimit(2)
            }

            if showPolicy, let name = entry.policyName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.block)
        .coveraCard()
    }
}

/// Writing one down. Nothing is required except the date, which is already set:
/// a half-filled note beats no note at all.
private struct CallLogEditor: View {
    @State var entry: CallLogEntry
    let onSave: (CallLogEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    Picker(String(localized: "Kind"), selection: $entry.kind) {
                        ForEach(CallLogEntry.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker(
                        String(localized: "When"),
                        selection: $entry.date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)

                    field(String(localized: "Spoke with"), text: $entry.person, prompt: String(localized: "Name, and department if you have it"))
                    field(String(localized: "Reference number"), text: $entry.reference, prompt: String(localized: "The number they read out"))
                    field(String(localized: "What was said"), text: $entry.notes, prompt: String(localized: "What they told you, and anything they promised"), lines: 4)
                    field(String(localized: "What you sent"), text: $entry.sent, prompt: String(localized: "Receipts, forms, a doctor's letter"), lines: 2)

                    Button {
                        onSave(entry)
                    } label: {
                        Text(String(localized: "Save"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.block)
                .padding(.bottom, Theme.Spacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .coveraScreen()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(String(localized: "Cancel"), action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryInk)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.tight)
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, prompt: String, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.tertiaryInk)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(lines...)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .textInputAutocapitalization(lines > 1 ? .sentences : .words)
                .padding(Theme.Spacing.step)
                .background(Theme.Palette.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
                )
        }
    }
}
