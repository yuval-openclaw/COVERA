import AuthenticationServices
import SwiftUI

/// Sign in or create an account: Apple, Google, or email and password.
///
/// Shown after the onboarding disclaimer and before the device lock. There is
/// nothing to protect on the device until someone has signed in, and signing in
/// is itself proof of identity, so a fresh sign-in skips the Face ID prompt.
struct LoginView: View {
    let onSignedIn: () -> Void

    @State private var model = LoginModel()
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.block) {
                Wordmark(size: .title2)
                    .padding(.top, Theme.Spacing.block)
                    .appearIn(0)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(model.creatingAccount
                         ? String(localized: "Create your account")
                         : String(localized: "Welcome back"))
                        .font(Theme.Typeface.display(.largeTitle))
                        .tracking(AppLanguage.current.isLatinScript ? -0.4 : 0)
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "Your policies stay private to your account."))
                        .font(.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                }
                .padding(.top, Theme.Spacing.block)
                .appearIn(1)

                // Apple's own button, as their guidelines require, and first:
                // where Sign in with Apple is offered it may not be shown below
                // another provider. It needs no configuration, so unlike Google
                // it is always available.
                appleButton.appearIn(2)

                // Shown only once a Google client is configured. A button that
                // cannot work is an App Review rejection (Guideline 2.1).
                if GoogleAuth.isConfigured {
                    googleButton.appearIn(2)
                }

                HStack(spacing: Theme.Spacing.step) {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 0.5)
                    Text(String(localized: "or"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.Palette.tertiaryInk)
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 0.5)
                }
                .accessibilityHidden(true)
                .appearIn(3)

                VStack(spacing: Theme.Spacing.tight + 2) {
                    field(isFocused: focus == .email) {
                        TextField(String(localized: "Email"), text: $model.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }
                    field(isFocused: focus == .password) {
                        SecureField(String(localized: "Password"), text: $model.password)
                            .textContentType(model.creatingAccount ? .newPassword : .password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit { submit() }
                    }
                    if model.creatingAccount {
                        Text(String(localized: "At least 10 characters."))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(Theme.Motion.unfold)
                    }
                }
                .appearIn(4)

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(Theme.Motion.unfold)
                }

                Button(action: submit) {
                    HStack(spacing: Theme.Spacing.tight) {
                        if model.isWorking { ProgressView().tint(Theme.Palette.background) }
                        Text(model.creatingAccount
                             ? String(localized: "Create account")
                             : String(localized: "Sign in"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSubmit)
                .appearIn(5)

                Button {
                    withAnimation(Theme.Motion.expand) {
                        model.creatingAccount.toggle()
                        model.clearError()
                    }
                } label: {
                    Text(model.creatingAccount
                         ? String(localized: "Already have an account? Sign in")
                         : String(localized: "New to Covera? Create an account"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .appearIn(6)

                Button {
                    focus = nil
                    Task { if await model.continueAsGuest() { onSignedIn() } }
                } label: {
                    Text(String(localized: "Continue as guest"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .disabled(model.isWorking)
                .appearIn(7)
                Text(String(localized: "A guest can't sign back in after signing out."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.tertiaryInk)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.screen + 4)
            .padding(.bottom, Theme.Spacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .coveraScreen()
        .animation(Theme.Motion.expand, value: model.errorMessage)
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
    }

    /// Apple's button, drawn by Apple. Its wording follows the device language
    /// rather than the in-app setting — that is Apple's, and not ours to change.
    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            focus = nil
            AppleAuth.prepare(request, nonce: model.startAppleNonce())
        } onCompletion: { result in
            Task { if await model.continueWithApple(result) { onSignedIn() } }
        }
        // Apple's guidance: a white button on a dark background. It is the
        // most prominent thing on the screen, which for a new account it
        // should be — it is the sign-in that hands over no address.
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .clipShape(Capsule())
        .disabled(model.isWorking)
        .opacity(model.isWorking ? 0.4 : 1)
    }

    private var googleButton: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Button {
                focus = nil
                Task { if await model.continueWithGoogle() { onSignedIn() } }
            } label: {
                HStack(spacing: Theme.Spacing.step) {
                    Text(verbatim: "G")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.background)
                        .frame(width: 26, height: 26)
                        .background(Theme.Palette.ink, in: Circle())
                        .accessibilityHidden(true)
                    Text(String(localized: "Continue with Google"))
                }
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .disabled(!GoogleAuth.isConfigured || model.isWorking)

        }
    }

    private func field<Content: View>(isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Spacing.block - 4)
            .frame(minHeight: 54)
            .coveraInset()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Palette.ink.opacity(0.35) : Theme.Palette.hairline,
                        lineWidth: isFocused ? 1 : 0.5
                    )
            )
            .animation(Theme.Motion.press, value: isFocused)
    }

    private func submit() {
        guard model.canSubmit else { return }
        focus = nil
        Task { if await model.submit() { onSignedIn() } }
    }
}

@MainActor
@Observable
final class LoginModel {
    var email = ""
    var password = ""
    var creatingAccount = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    var canSubmit: Bool {
        email.contains("@") && password.count >= (creatingAccount ? 10 : 1) && !isWorking
    }

    func clearError() { errorMessage = nil }

    func submit() async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let response = try await APIClient.shared.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                createAccount: creatingAccount
            )
            try await Session.shared.signIn(token: response.token)
            password = ""
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func continueAsGuest() async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await Session.shared.signIn(token: try await APIClient.shared.signInAsGuest().token)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Kept from the moment the button is tapped until the token comes back:
    /// the server checks that this sign-in is the one Apple signed.
    private var appleNonce = ""

    func startAppleNonce() -> String {
        appleNonce = AppleAuth.newNonce()
        return appleNonce
    }

    func continueWithApple(_ result: Result<ASAuthorization, Error>) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let token = try AppleAuth.identityToken(from: result)
            let response = try await APIClient.shared.signInWithApple(identityToken: token, nonce: appleNonce)
            try await Session.shared.signIn(token: response.token)
            return true
        } catch AppleAuthError.cancelled {
            return false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func continueWithGoogle() async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let idToken = try await GoogleAuth().signIn()
            let response = try await APIClient.shared.signInWithGoogle(idToken: idToken)
            try await Session.shared.signIn(token: response.token)
            return true
        } catch GoogleAuthError.cancelled {
            return false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

#if DEBUG
#Preview {
    LoginView(onSignedIn: {}).preferredColorScheme(.dark)
}
#endif
