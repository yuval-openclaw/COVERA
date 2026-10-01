import SwiftUI
import UniformTypeIdentifiers

/// The Policies tab, behind `PolicyLock`. While it is closed, nothing of the
/// library is in the view tree, so a sheet that was open over it goes too.
struct PolicyGate<Content: View>: View {
    let lock: PolicyLock
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch lock.state {
        case .unlocked: content()
        case .locked: EnterCodeView(lock: lock)
        case .needsCode: CreateCodeView(lock: lock)
        }
    }
}

// MARK: - Choosing a code

private struct CreateCodeView: View {
    let lock: PolicyLock

    private enum Stage: Equatable { case choose, confirm(String), save(String) }
    @State private var stage: Stage = .choose
    @State private var entry = ""
    @State private var message: String?
    @State private var copied = false
    @State private var confirmingSkip = false

    var body: some View {
        LockLayout(
            icon: "lock.shield",
            title: title,
            subtitle: subtitle,
            message: message
        ) {
            if case .save(let code) = stage {
                savePanel(code)
            } else {
                CodeField(entry: $entry, onComplete: submit)
            }
        }
        .alert(String(localized: "Skip saving your code?"), isPresented: $confirmingSkip) {
            Button(String(localized: "Save it now"), role: .cancel) {}
            Button(String(localized: "Skip anyway")) { finish() }
        } message: {
            Text(String(localized: "This code is what keeps your policies private if someone else holds your phone. If you forget it, you will have to sign in again to choose a new one."))
        }
    }

    private var title: String {
        switch stage {
        case .choose: String(localized: "Protect your policies")
        case .confirm: String(localized: "Enter it again")
        case .save: String(localized: "Keep your code safe")
        }
    }

    private var subtitle: String {
        switch stage {
        case .choose: String(localized: "Choose a 6-digit code. You will enter it to open your policies.")
        case .confirm: String(localized: "To make sure it is the code you meant.")
        case .save: String(localized: "Write it down or save it in your password manager. You will need it every time you open your policies.")
        }
    }

    private func submit(_ code: String) {
        switch stage {
        case .choose:
            message = nil
            stage = .confirm(code)
        case .confirm(let first) where first == code:
            stage = .save(code)
        case .confirm:
            message = String(localized: "The codes did not match. Choose one again.")
            stage = .choose
        case .save:
            break
        }
    }

    private func savePanel(_ code: String) -> some View {
        VStack(spacing: Theme.Spacing.block) {
            Text(verbatim: code.prefix(3) + " " + code.suffix(3))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Palette.ink)
                .privacySensitive()
                .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))

            Button {
                // Local to this device and gone after a minute: a code left on
                // the clipboard is readable by whatever is pasted into next.
                UIPasteboard.general.setItems([[UTType.plainText.identifier: code]],
                                              options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                withAnimation(Theme.Motion.press) { copied = true }
            } label: {
                Label(copied ? String(localized: "Copied for one minute") : String(localized: "Copy code"),
                      systemImage: copied ? "doc.on.doc.fill" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.cited)
            }

            VStack(spacing: Theme.Spacing.step) {
                Button(String(localized: "I have saved it")) { finish() }
                    .buttonStyle(PrimaryButtonStyle())
                Button(String(localized: "Skip")) { confirmingSkip = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryInk)
            }
            .padding(.top, Theme.Spacing.block)
        }
    }

    private func finish() {
        guard case .save(let code) = stage else { return }
        do {
            try lock.set(code: code)
        } catch {
            message = String(localized: "The code could not be saved on this device. Try again.")
            stage = .choose
        }
    }
}

// MARK: - Entering it

private struct EnterCodeView: View {
    let lock: PolicyLock
    @State private var entry = ""
    @State private var message: String?
    @State private var confirmingForgot = false
    @State private var exhausted = false

    var body: some View {
        LockLayout(
            icon: "lock",
            title: String(localized: "Your policies are locked"),
            subtitle: String(localized: "Enter your code to open them."),
            message: message
        ) {
            CodeField(entry: $entry, onComplete: submit)
            Button(String(localized: "Forgot your code?")) { confirmingForgot = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.cited)
                .padding(.top, Theme.Spacing.block)
        }
        .alert(String(localized: "Forgot your code?"), isPresented: $confirmingForgot) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Sign out")) { Task { await signOut() } }
        } message: {
            Text(String(localized: "Sign out, then sign back in to choose a new code. Your policies are stored safely and nothing is lost."))
        }
        .alert(String(localized: "Too many wrong codes"), isPresented: $exhausted) {
            Button(String(localized: "OK")) { Task { await signOut() } }
        } message: {
            Text(String(localized: "For your safety you have been signed out. Sign back in to choose a new code."))
        }
    }

    private func submit(_ code: String) {
        switch lock.attempt(code) {
        case .accepted:
            message = nil
        case .rejected(let left):
            message = String(localized: "Wrong code. \(left) tries left.")
        case .exhausted:
            exhausted = true
        }
    }

    /// Signing out clears the code (see `CoveraApp`), which is how a new one
    /// gets chosen.
    private func signOut() async {
        await APIClient.shared.signOut()
        await Session.shared.signOut()
        AuthState.shared.didSignOut()
    }
}

// MARK: - Shared pieces

private struct LockLayout<Controls: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let message: String?
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.elevated, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.Typeface.display(.title))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.block + 4)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.tight)

            VStack(spacing: 0) { controls() }
                .padding(.top, Theme.Spacing.section)

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.caution)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Spacing.block)
                    .transition(Theme.Motion.unfold)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.screen + 12)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coveraScreen()
        .animation(Theme.Motion.press, value: message)
    }
}

/// Six dots over an invisible number field. Typing fills the dots; the sixth
/// digit submits.
private struct CodeField: View {
    @Binding var entry: String
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool
    /// One attempt per code, even if trimming the input fires a second change.
    @State private var submitting = false

    var body: some View {
        ZStack {
            TextField("", text: $entry)
                .keyboardType(.numberPad)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityLabel(Text(String(localized: "Code")))
                .accessibilityValue(Text(String(localized: "\(entry.count) of 6 digits")))
            HStack(spacing: 18) {
                ForEach(0..<PolicyLock.length, id: \.self) { i in
                    Circle()
                        .fill(i < entry.count ? Theme.Palette.ink : Color.clear)
                        .overlay(Circle().strokeBorder(Theme.Palette.ink.opacity(0.35), lineWidth: 1.5))
                        .frame(width: 16, height: 16)
                }
            }
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .onChange(of: entry) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(PolicyLock.length))
            if digits != value { entry = digits }
            guard digits.count == PolicyLock.length, !submitting else { return }
            submitting = true
            onComplete(digits)
            // Cleared on the next turn of the run loop, not inside this change:
            // cleared here, the old digits stayed in the text field and the
            // next code was typed after them.
            DispatchQueue.main.async {
                entry = ""
                submitting = false
            }
        }
    }
}
