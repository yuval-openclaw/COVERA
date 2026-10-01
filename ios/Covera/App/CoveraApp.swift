import SwiftUI

@main
struct CoveraApp: App {
    @State private var policyLock = PolicyLock()
    @State private var auth = AuthState.shared
    /// The signed-in account's plan, library and call log, replaced on
    /// sign-out because they belong to that account.
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
                    LoginView(onSignedIn: { auth.didSignIn() })
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
                    RootView(policyLock: policyLock, workspace: workspace)
                }
            }
            .overlay {
                // The app-switcher snapshot is taken as the app goes inactive,
                // before `.background` arrives. Covering the screen here keeps
                // policy text out of that snapshot; the code itself is asked
                // for only after a real trip to the background.
                if scenePhase != .active && disclaimerAccepted {
                    PrivacyShield()
                }
            }
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
            // Close the policies again as soon as the app leaves the
            // foreground, so they are never open in the app switcher.
            if phase == .background { policyLock.lock() }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // A new workspace on every change of account: after sign-in it
            // opens that account's call log; after sign-out, or a session the
            // server rejected, nothing of the last account's carries over,
            // including its code.
            workspace = Workspace()
            if !signedIn { policyLock.reset() }
        }
    }
}

/// What one signed-in account has open: its plan, its library, its call log,
/// and where it was in the app. Replaced when the account signs out.
@MainActor
@Observable
final class Workspace {
    var tab: AppTab = .home
    var showingGuidance = false
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
        callLog = CallLogStore(accountID: Session.shared.accountID)
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
    let policyLock: PolicyLock
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

            PolicyGate(lock: policyLock) {
                DocumentsView(
                    model: documents,
                    callLog: callLog,
                    onStartGuidance: { workspace.showingGuidance = true }
                )
            }
                .tabItem { Label(String(localized: "Policies"), systemImage: "doc.text") }
                .tag(AppTab.policies)
                .id(language)

            AccountView()
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
