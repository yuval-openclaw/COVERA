import SwiftUI

@main
struct CoveraApp: App {
    @State private var lock = AppLock()
    @State private var auth = AuthState.shared
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
                    RootView(lock: lock)
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
            // never sitting open in the app switcher.
            if phase == .background { lock.lock() }
        }
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
    @State private var tab: AppTab = .home
    @State private var guidance: GuidanceModel
    @State private var documents: DocumentsModel
    @State private var callLog: CallLogStore
    @State private var showingGuidance = false
    // Tabs are re-identified on a language change so every string redraws,
    // while the tab, the plan and the library survive it.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.en.rawValue

    init(lock: AppLock) {
        self.lock = lock
        #if DEBUG
        if PreviewData.isDemo {
            _guidance = State(initialValue: PreviewData.guidanceModel())
            _documents = State(initialValue: DocumentsModel(sample: PreviewData.documents))
            _callLog = State(initialValue: CallLogStore(sample: PreviewData.callLog))
            return
        }
        #endif
        _guidance = State(initialValue: GuidanceModel())
        _documents = State(initialValue: DocumentsModel())
        _callLog = State(initialValue: CallLogStore())
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(
                guidance: guidance,
                documents: documents,
                callLog: callLog,
                onOpenGuidance: { showingGuidance = true },
                onNewGuidance: {
                    guidance.reset()
                    showingGuidance = true
                },
                onShowPolicies: { tab = .policies },
                onShowAccount: { tab = .account }
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
                onStartGuidance: { showingGuidance = true }
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
        .fullScreenCover(isPresented: $showingGuidance) {
            GuidanceFlowView(
                model: guidance,
                onClose: { showingGuidance = false },
                onOpenAccount: {
                    showingGuidance = false
                    tab = .account
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
            case "plan": showingGuidance = true
            case "policies": tab = .policies
            case "ask": tab = .ask
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

struct LockScreen: View {
    let lock: AppLock

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

            Text(String(localized: "Your insurance documents are behind Face ID or your passcode."))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.tight)

            Spacer()

            Button {
                Task { await lock.unlock() }
            } label: {
                Label(String(localized: "Unlock"), systemImage: "faceid")
            }
            .buttonStyle(PrimaryButtonStyle())

            Wordmark(size: .headline)
                .padding(.top, Theme.Spacing.block)
        }
        .padding(.horizontal, Theme.Spacing.screen + 12)
        .padding(.bottom, Theme.Spacing.block)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coveraScreen()
        .task { await lock.unlock() }
    }
}
