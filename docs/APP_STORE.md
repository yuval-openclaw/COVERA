# App Store submission readiness

What is done in the repository, and what a human has to do in a browser or in
Xcode. Nothing here can be finished by the code alone — the remaining items are
account, legal and asset work.

## Done in the repo

| Requirement | Where |
| --- | --- |
| Camera / Photos / Calendar usage strings | `ios/Covera/Info.plist` |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | `ios/Covera/PrivacyInfo.xcprivacy` |
| Keychain + Associated Domains entitlements | `ios/Covera/Covera.entitlements` |
| App icon slot (1024, no alpha) | `ios/Covera/Resources/Assets.xcassets/AppIcon.appiconset` — **placeholder art** |
| 6-digit code on the Policies tab, re-locks on backgrounding | `ios/Covera/Core/PolicyLock.swift`, `ios/Covera/Features/Dashboard/PolicyLockView.swift` |
| Mandatory onboarding disclaimer, no skip (1.4.1 / 5.1.1) | `ios/Covera/Features/Onboarding/OnboardingDisclaimerView.swift` |
| In-app account deletion (5.1.1(v)) | `ios/Covera/Features/Account/AccountView.swift` → `DELETE /account` |
| Full data export | `AccountView` → `GET /account/export` |
| Export compliance answer (`ITSAppUsesNonExemptEncryption = false`) | `ios/Covera/Info.plist` — **verify, see below** |
| Encryption at rest, per-user isolation | `api/src/storage/`, `api/src/db/user-scope.test.ts` |

## Must be done by a person

### Blocking

1. **Apple Developer Program membership** ($99/yr). Nothing can be uploaded
   without it.
2. **Xcode.** Not installed on this machine. Generate the project first:
   ```
   brew install xcodegen
   cd ios && xcodegen generate && open Covera.xcodeproj
   ```
3. **Real app icon.** The committed 1024×1024 PNG is a placeholder mark, not a
   designed icon. Replace it.
4. **Privacy Policy URL.** The pages are in `site/`. Fill the blanks
   (`site/check.sh`), deploy, and enter `<address>/privacy.html` as the Privacy
   Policy URL in App Store Connect. See `docs/LEGAL.md`.
5. **Sign in with Apple.** Email/password and Google sign-in are built. Because Google
   is a third-party login, Guideline 4.8 requires also offering Sign in with Apple
   before submission. Google itself needs an iOS OAuth client created in Google
   Cloud Console (see `CLAUDE.md` → Authentication).
6. **Point the client at a deployed API.** `CoveraAPIBaseURL` in
   `ios/project.yml` is `http://localhost:3000`. The ATS localhost exception in
   `Info.plist` should be removed for a release build.

### Store listing

7. **App Privacy "nutrition label."** Answer it to match
   `PrivacyInfo.xcprivacy`: Health, Financial Info, Contact Info (email), and
   User Content — all linked to identity, all for App Functionality, none for
   tracking. A mismatch between the manifest and the label is a rejection.
8. **Category.** Medical is the honest primary category; Finance is a defensible
   secondary. Medical attracts closer review — expect questions about whether
   the app diagnoses or advises. It does neither, and the onboarding screen and
   the standing disclaimer say so.
9. **Screenshots** for 6.9" and 6.5" iPhone, plus 13" iPad if the iPad build
   ships. Use the guidance screen showing a citation expanded — it is the
   product's argument in one image.
10. **Review notes.** Give the reviewer a demo account with policies already
    uploaded; the app is empty and unevaluable without documents. State plainly:
    "This app does not provide medical advice or insurance advice. It quotes the
    user's own uploaded policy documents and cites the page for every figure."
11. **Export compliance.** The app itself uses only standard TLS and Keychain,
    so the exemption holds. Confirm this with counsel — the *server* performs
    AES-256-GCM, which does not change the app's answer but is worth stating
    correctly if asked.

### Before public launch

12. **Legal positioning review.** Paid insurance advice is a licensed activity in
    many jurisdictions. Confirm before charging for anything.
13. **Any paid tier must use StoreKit**, not a web checkout (Guideline 3.1.1).
    No payment code exists yet, which is the right time to decide this.
14. **TestFlight** with real policy documents from at least two insurers before
    submitting.

## Rejection risks specific to this app

- **Medical category scrutiny.** Mitigated by the onboarding screen, the
  server-side disclaimer on every response, and the fact that the app withholds
  any step it cannot trace to a document.
- **Account deletion.** Implemented in-app and unconditional. Reviewers test this
  path directly.
- **Privacy manifest drift.** If a data type is added server-side, the manifest
  and the nutrition label must both be updated or the next release is rejected.

## Accessibility Nutrition Labels (App Store Connect)

Declare a feature only when someone relying on it can complete the app's common tasks — the same
rule `site/accessibility.html` follows. Checked on 2026-10-01 (iOS 26 simulator):

| Feature | Declare? | Why |
|---|---|---|
| Sufficient Contrast | **Yes** | Every text colour clears WCAG AA on `surface` and `background` (Theme.swift) |
| Differentiate Without Color Alone | **Yes** | Every coloured chip also says what it means in words |
| Reduced Motion | **Yes** | `Theme.Motion` honours Reduce Motion |
| Larger Text | **Not yet** | Screens scale and scroll at AX5, but plan action labels and Ask suggestions truncate |
| VoiceOver | **Not yet** | Labels exist; no full screen-by-screen VoiceOver pass yet |
| Voice Control | **Not yet** | Untested |
| Dark Interface | No | The app has one appearance, light |
| Captions / Audio Descriptions | No | The app plays no media |
