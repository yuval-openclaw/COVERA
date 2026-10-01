import SwiftUI

/// Ask anything about your policies. Every answer is held to the same rule as
/// plans: a figure only with a citation from the reader's own document, and a
/// plain "ask your insurer" when the documents are silent.
struct ChatView: View {
    @State private var model: ChatModel
    @FocusState private var focused: Bool

    init(model: ChatModel = ChatModel()) {
        _model = State(initialValue: model)
    }

    private let suggestions = [
        String(localized: "What do I need before a planned surgery?"),
        String(localized: "How long do I have to submit a claim?"),
        String(localized: "Is dental treatment covered?"),
        String(localized: "Which documents does a claim need?"),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                    ScreenHeader(
                        eyebrow: String(localized: "Assistant"),
                        title: String(localized: "Ask Clausa"),
                        subtitle: String(localized: "Answers come only from your own policies, with the page they came from.")
                    )
                    .appearIn(0)

                    if model.messages.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Eyebrow(text: String(localized: "Try asking"))
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                                Button {
                                    Task { await model.send(text) }
                                } label: {
                                    HStack {
                                        Text(text).font(.subheadline).foregroundStyle(Theme.Palette.ink)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(Theme.Palette.tertiaryInk)
                                    }
                                    .padding(Theme.Spacing.step + 2)
                                    .coveraCard()
                                }
                                .buttonStyle(PressableStyle())
                                .appearIn(index + 1)
                            }
                        }
                    }

                    ForEach(model.messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                            .transition(Theme.Motion.arrive)
                    }

                    if model.isThinking {
                        TypingIndicator().id("typing").transition(.opacity)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.block)
                .animation(Theme.Motion.expand, value: model.messages.count)
                .animation(Theme.Motion.appear, value: model.isThinking)
            }
            .scrollDismissesKeyboard(.interactively)
            .coveraScreen()
            .onChange(of: model.messages.count) {
                withAnimation(Theme.Motion.expand) { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.tight) {
            TextField(String(localized: "Ask about your policies"), text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, Theme.Spacing.block - 4)
                .padding(.vertical, Theme.Spacing.step)
                .background(Theme.Palette.inset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button {
                let text = model.draft
                Task { await model.send(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.background)
                    .frame(width: 44, height: 44)
                    .background(Theme.Palette.ink, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!model.canSend)
            .opacity(model.canSend ? 1 : 0.35)
            .accessibilityLabel(String(localized: "Send"))
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.tight)
        .background(.ultraThinMaterial)
    }
}

private struct MessageView: View {
    let message: ChatMessage
    @State private var openCitation: SourceCitation?

    var body: some View {
        switch message.kind {
        case let .user(text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.background)
                    .padding(.horizontal, Theme.Spacing.block - 4)
                    .padding(.vertical, Theme.Spacing.step)
                    .background(Theme.Palette.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case let .reply(reply):
            VStack(alignment: .leading, spacing: Theme.Spacing.step) {
                Text(reply.answer)
                    .font(.body)
                    .foregroundStyle(reply.withheld ? Theme.Palette.secondaryInk : Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !reply.citations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.tight) {
                            ForEach(reply.citations, id: \.self) { citation in
                                Button {
                                    withAnimation(Theme.Motion.expand) {
                                        openCitation = openCitation == citation ? nil : citation
                                    }
                                } label: {
                                    Pill(text: String(localized: "Page \(citation.page)"), systemImage: "doc.text", tint: Theme.Palette.cited)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }

                if let citation = openCitation {
                    Text("“\(citation.verbatimQuote)”")
                        .font(Theme.Typeface.quote)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Theme.Spacing.step + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coveraInset()
                        .transition(Theme.Motion.unfold)
                }

                if let ask = reply.askInsurer {
                    VStack(alignment: .leading, spacing: Theme.Spacing.hair) {
                        Text(String(localized: "Ask your insurer"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.unstated)
                        Text(ask).font(.callout).foregroundStyle(Theme.Palette.ink)
                    }
                    .padding(Theme.Spacing.step + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.unstated.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous))
                }

                Text(reply.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .coveraCard()
        case let .error(text):
            NoticeCard(icon: "exclamationmark.triangle", tint: Theme.Palette.caution, title: String(localized: "No answer"), message: text)
        }
    }
}

private struct TypingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Palette.secondaryInk)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase ? 1 : 0.5)
                    .opacity(phase ? 1 : 0.4)
                    .animation(
                        Theme.Motion.reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.block)
        .padding(.vertical, Theme.Spacing.step + 4)
        .background(Theme.Palette.surface, in: Capsule())
        .onAppear { phase = true }
        .accessibilityLabel(String(localized: "Reading your policies"))
    }
}

// MARK: - Model

struct ChatMessage: Identifiable {
    enum Kind { case user(String), reply(ChatReply), error(String) }
    let id = UUID()
    let kind: Kind
}

@MainActor
@Observable
final class ChatModel {
    var draft = ""
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    private var isSample = false

    init() {}

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    func send(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(ChatMessage(kind: .user(question)))
        isThinking = true
        defer { isThinking = false }

        #if DEBUG
        if isSample {
            try? await Task.sleep(for: .seconds(1.2))
            messages.append(ChatMessage(kind: .reply(PreviewData.chatReply)))
            return
        }
        #endif

        // Only the text of the conversation is sent; replies are re-verified
        // server-side on every turn, never trusted from history.
        let history: [(role: String, content: String)] = messages.suffix(10).compactMap {
            switch $0.kind {
            case let .user(t): ("user", t)
            case let .reply(r): ("assistant", r.answer)
            case .error: nil
            }
        }
        do {
            let reply = try await APIClient.shared.chat(history: history)
            messages.append(ChatMessage(kind: .reply(reply)))
        } catch {
            messages.append(ChatMessage(kind: .error((error as? APIError)?.errorDescription ?? error.localizedDescription)))
        }
    }

    #if DEBUG
    init(sample: Bool) { isSample = sample }
    #endif
}

#if DEBUG
#Preview {
    ChatView(model: ChatModel(sample: true)).preferredColorScheme(.dark)
}
#endif
