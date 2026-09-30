import SwiftUI

@main
struct CoveraApp: App {
    @State private var lock = AppLock()
    @State private var auth = AuthState.shared
    /// The signed-in account's plan, library and call log. Held here, above the
    /// lock, so locking can take the whole interface away without losing a plan
    /// in progress; replaced on sign-out, because it belongs to that account.
    @State private var workspace = Workspace()
    // The first-launch explanation of what Covera is. Agreement to the terms is
    // separate and per account (ConsentView, after sign-in).
    @AppStorage("covera.onboardingSeen") private var disclaimerAccepted = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.en.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if !disclaimerAccepted {
                    // Guideline 1.4.1 / 5.1.1: what this app is and is not, before
                    // anyone uploads a medical document.
                    OnboardingDisclaimerView(onAccept: { disclaimerAccepted = true })
                } else if !auth.isSignedIn && !isDemo {
                    LoginView(onSignedIn: {
                        lock.grantAfterSignIn()
                        auth.didSignIn()
                    })
                    .transition(Theme.Motion.arrive)
                } else if !isDemo && auth.hasAgreed != true {
                    // After sign-in and before anything else: the three
                    // agreements, recorded on the server. Returning users who
                    // already agreed to this version pass straight through.
                    if auth.hasAgreed == false {
                        ConsentView(onAgreed: { auth.didAgree() })
                            .transition(Theme.Motion.arrive)
                    } else {
                        ProgressView()
                            .tint(Theme.Palette.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .coveraScreen()
                            .task { await auth.refreshAgreement(version: Legal.version) }
                    }
                } else {
                    gated
                }
            }
            .overlay {
                // The app-switcher snapshot is taken as the app goes inactive,
                // before `.background` arrives. Covering the screen here keeps
                // policy text out of that snapshot without re-locking — which
                // matters, because the Face ID sheet itself makes the app
                // inactive and a lock here would fight its own unlock.
                if scenePhase != .active && disclaimerAccepted {
                    PrivacyShield()
                }
            }
            .animation(Theme.Motion.appear, value: lock.state)
            .animation(Theme.Motion.appear, value: disclaimerAccepted)
            .animation(Theme.Motion.appear, value: auth.isSignedIn)
            .animation(Theme.Motion.appear, value: auth.hasAgreed)
            .tint(Theme.Palette.cited)
            // One committed look. The palette is designed for black and is not
            // meant to be inverted, so system chrome — alerts, keyboards, share
            // sheets — is pinned dark to match.
            .preferredColorScheme(Theme.appearance == .light ? .light : .dark)
            .environment(\.layoutDirection, (AppLanguage(rawValue: language) ?? .en).isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-lock as soon as the app leaves the foreground, so a document is
            // never sitting open in the app switcher. Remember whether the plan
            // was open first: someone who leaves to call their insurer should
            // come back to the step they were on.
            if phase == .background {
                workspace.resumeGuidance = workspace.showingGuidance
                lock.lock()
            }
            // Asking while in the background fails at once, so the prompt
            // waits until the app is really in front again.
            if phase == .active, lock.promptOnActive, lock.state == .locked, auth.isSignedIn || isDemo {
                Task { await lock.unlock() }
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // Sign-out, or a session the server rejected: nothing of this
            // account's may carry over to the next one.
            if !signedIn { workspace = Workspace() }
        }
    }

    /// Nothing that shows policy data exists in the view tree until the lock is
    /// open — not the tabs, not a sheet, not a resumed plan. Removing the root
    /// rather than covering it also dismisses whatever it had presented, which
    /// an overlay could not: sheets and full-screen covers sit above it.
    @ViewBuilder
    private var gated: some View {
        switch lock.state {
        case .unlocked:
            RootView(lock: lock, workspace: workspace)
        case .locked:
            LockScreen(lock: lock)
        case .unavailable(let reason):
            LockScreen(lock: lock, unavailableReason: reason)
        }
    }
}

/// What one signed-in account has open: its plan, its library, its call log,
/// and where it was in the app. Outlives the lock; not the account.
@MainActor
@Observable
final class Workspace {
    var tab: AppTab = .home
    var showingGuidance = false
    /// The plan was open when the app locked; reopen it once unlocked.
    var resumeGuidance = false
    let guidance: GuidanceModel
    let documents: DocumentsModel
    let callLog: CallLogStore

    init() {
        #if DEBUG
        if PreviewData.isDemo {
            guidance = PreviewData.guidanceModel()
            documents = DocumentsModel(sample: PreviewData.documents)
            callLog = CallLogStore(sample: PreviewData.callLog)
            return
        }
        #endif
        guidance = GuidanceModel()
        documents = DocumentsModel()
        callLog = CallLogStore()
    }
}

private var isDemo: Bool {
    #if DEBUG
    PreviewData.isDemo
    #else
    false
    #endif
}

enum AppTab: Hashable {
    case home, ask, policies, account
}

/// Three places, and guidance over the top of all of them.
///
/// Guidance is not a tab: it is a task with a beginning and an end, so it runs
/// as one focused flow presented over whichever screen started it. The plan
/// survives closing the flow, so Home can offer to pick it up again.
struct RootView: View {
    let lock: AppLock
    @Bindable var workspace: Workspace
    // Tabs are re-identified on a language change so every string redraws,
    // while the tab, the plan and the library survive it.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.en.rawValue

    private var guidance: GuidanceModel { workspace.guidance }
    private var documents: DocumentsModel { workspace.documents }
    private var callLog: CallLogStore { workspace.callLog }

    var body: some View {
        TabView(selection: $workspace.tab) {
            HomeView(
                guidance: guidance,
                documents: documents,
                callLog: callLog,
                onOpenGuidance: { workspace.showingGuidance = true },
                onNewGuidance: {
                    guidance.reset()
                    workspace.showingGuidance = true
                },
                onShowPolicies: { workspace.tab = .policies },
                onShowAccount: { workspace.tab = .account }
            )
            .tabItem { Label(String(localized: "Home"), systemImage: "house") }
            .tag(AppTab.home)
            .id(language)

            chat
                .tabItem { Label(String(localized: "Ask"), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppTab.ask)
                .id(language)

            DocumentsView(
                model: documents,
                callLog: callLog,
                onStartGuidance: { workspace.showingGuidance = true }
            )
                .tabItem { Label(String(localized: "Policies"), systemImage: "doc.text") }
                .tag(AppTab.policies)
                .id(language)

            AccountView(lock: lock)
                .tabItem { Label(String(localized: "Account"), systemImage: "person.crop.circle") }
                .tag(AppTab.account)
                .id(language)
        }
        .tint(Theme.Palette.ink)
        .environment(\.locale, Locale(identifier: language))
        .fullScreenCover(isPresented: $workspace.showingGuidance) {
            GuidanceFlowView(
                model: guidance,
                onClose: { workspace.showingGuidance = false },
                onOpenAccount: {
                    workspace.showingGuidance = false
                    workspace.tab = .account
                }
            )
            .coveraLayoutDirection()
        }
        .overlay {
            if documents.isUploading {
                UploadingOverlay().transition(Theme.Motion.arrive)
            }
        }
        .animation(Theme.Motion.appear, value: documents.isUploading)
        .onAppear {
            // Back from the lock: return to the plan if it was open.
            if workspace.resumeGuidance {
                workspace.resumeGuidance = false
                workspace.showingGuidance = true
            }
        }
        #if DEBUG
        .onAppear {
            switch PreviewData.shot {
            case "plan": workspace.showingGuidance = true
            case "policies": workspace.tab = .policies
            case "ask": workspace.tab = .ask
            default: break
            }
        }
        #endif
    }
}

extension RootView {
    @ViewBuilder
    var chat: some View {
        #if DEBUG
        if PreviewData.isDemo { ChatView(model: ChatModel(sample: true)) } else { ChatView() }
        #else
        ChatView()
        #endif
    }
}

private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            Wordmark(size: .title)
        }
        .accessibilityHidden(true)
    }
}

/// In front of everything while the app is locked. With `unavailableReason`,
/// the device has no passcode or biometrics at all; see `AppLock.continueWithoutLock`.
struct LockScreen: View {
    let lock: AppLock
    var unavailableReason: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.elevated, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                .accessibilityHidden(true)

            Text(String(localized: "Locked"))
                .font(Theme.Typeface.display(.largeTitle))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, Theme.Spacing.block + 4)

            Text(unavailableReason ?? String(localized: "Your insurance documents are behind Face ID or your passcode."))
                .font(.subheadline)
                .foregroundStyle(unavailableReason == nil ? Theme.Palette.secondaryInk : Theme.Palette.caution)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.tight)

            Spacer()

            if unavailableReason == nil {
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label(String(localized: "Unlock"), systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(String(localized: "Continue")) { lock.continueWithoutLock() }
                    .buttonStyle(PrimaryButtonStyle())
                Button(String(localized: "Try again")) { Task { await lock.unlock() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.cited)
                    .padding(.top, Theme.Spacing.step)
            }

            Wordmark(size: .headline)
                .padding(.top, Theme.Spacing.block)
        }
        .padding(.horizontal, Theme.Spacing.screen + 12)
        .padding(.bottom, Theme.Spacing.block)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coveraScreen()
        // At launch the app may already be active; otherwise the scene-phase
        // handler asks once it is. Never with nothing to ask with.
        .task { if unavailableReason == nil, scenePhase == .active { await lock.unlock() } }
    }
}
