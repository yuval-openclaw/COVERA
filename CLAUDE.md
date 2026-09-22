# Covera

Users upload their health insurance policies. The app remembers them accurately and, during
a medical event, guides the user step by step based strictly on what their policies say.

## The rule everything else serves

Never invent a number. Every percentage, amount, cap, waiting period and deadline shown to a
user must trace to their own document by id, page and verbatim quote. When a policy is silent
or ambiguous, say so and route the user to the insurer. Guessing is the failure mode that
matters — a wrong figure during a medical crisis is worse than no figure.

This is enforced structurally, not by prompt wording:

- `api/src/schema/policy.ts` — a figure can only exist as `stated` with a citation attached.
  `not_stated` and `ambiguous` are separate variants. There is deliberately no field in which
  to record a preferred reading of ambiguous text.
- `api/src/ingestion/verify.ts` — checks the quote actually appears on the cited page, and
  that every number in a value appears in its own supporting quote. Catches a real quote
  paired with an invented figure.
- `api/src/ingestion/snap.ts` runs just before it: when a quote has every figure and nearly
  all the words of a page passage but in a different order (Hebrew text layers store runs
  out of printed order), the quote is replaced with the exact page text. It never changes a
  figure and never decides anything; the verifier still does.
- A field still unproven after the last attempt becomes `unverified` (no figure; "check your
  policy or ask your insurer") rather than failing the whole document — never for exclusions,
  claim steps or required documents, never for more than a quarter of fields, and never set
  by the model (`ingestion/unverified.ts`). `not_stated` still means only "the document is
  silent".
- `api/src/guidance/verify-steps.ts` — the same gate on the way out. A step may assert a
  figure only if its own citation contains it; an uncited step may carry no figure at all,
  including inside the question it tells the user to ask; and prose (`summary`, `conflicts`,
  `phone_script`, `draft_claim_email`) may only repeat figures a *surviving* step proved —
  the script and email go to the insurer, so they use `[placeholders]` for anything else.
  Anything else is withheld and reported in `withheld[]` rather than shown with a caveat.
- `api/src/db/user-scope.test.ts` — fails the build if a query against a user-owned table
  omits `user_id`. Cross-account isolation checked mechanically, not by review.

If extraction output fails the verifier, the extraction is wrong. Never loosen the verifier.

## Stack

TypeScript API (Fastify) · Postgres 17 + pgvector · local-disk or S3 blob storage with
app-level AES-256-GCM · Gemini API (generation and embeddings, over REST) · SwiftUI client.

Memory of policy data is retrieval over stored documents, never model recall — every answer
re-reads the source and returns cited snippets.

## Layout

```
api/src/
  schema/policy.ts        extraction contract — the citation guarantee
  ingestion/verify.ts     mechanical citation verification + tests
  guidance/               retrieval, plan assembly, the outbound citation gate
  routes/account.ts       export + irreversible delete
  db/                     pool, migration runner, SQL migrations
  storage/                encrypted document store (local | s3)
  ai/gemini.ts            Gemini REST client, model names, structured JSON output
ios/
  project.yml             XcodeGen spec; the .xcodeproj is generated, not committed
  Covera/Core/            API client, Keychain session, design system, scanner, legal URLs
  Covera/Features/        Home hub, guidance flow + plan, policies, account, onboarding
site/                     privacy policy, terms, health-data policy, accessibility (static)
docs/                     App Store readiness, legal readiness (LEGAL.md)
.claude/agents/           policy-extraction, guidance-engine, ui, qa-safety
```

## Commands

```
cd api
npm run migrate      # apply SQL migrations
npm run dev          # API on :3000
npm test             # citation verification suite
npm run typecheck
```

Postgres runs via `brew services start postgresql@17`; binaries are keg-only at
`/opt/homebrew/opt/postgresql@17/bin`. On this Mac the API runs as the LaunchAgent
`com.covera.api` through `api/scripts/start-local.sh`, which clears a stale `postmaster.pid`
(a reboot can hand its pid to another process) before starting.

iOS (Xcode is installed but not `xcode-select`ed, so prefix `DEVELOPER_DIR`):

```
cd ios && xcodegen generate          # after adding or removing any Swift file
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Covera.xcodeproj -scheme Covera -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
xcrun simctl launch booted com.covera.app -CoveraDemo                      # sample data, no API
xcrun simctl launch booted com.covera.app                                  # live API, sign in
```

**Never build with `CODE_SIGNING_ALLOWED=NO`.** The app still launches, but without its
entitlements the Keychain keeps nothing: the saved account id disappears and every screen says
"not connected", which looks like a server problem and is not one.

Live API on the simulator: start the API (`covera-api` in `.claude/launch.json`), launch without
`-CoveraDemo`, and sign in with email and password. A fresh sign-in skips the Face ID prompt; on
later launches the lock is real. Enrol simulated Face ID once with
`xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged 1` followed by
`... notifyutil -p com.apple.BiometricKit.enrollmentChanged`, then pass each prompt with
`... notifyutil -p com.apple.BiometricKit_Sim.pearl.match`.

## Authentication

Email + password, and Google. `routes/auth.ts` issues a random session token; the server stores
only its SHA-256 (`sessions`, migration 004) and passwords only as salted scrypt hashes
(`auth/passwords.ts`). Every data route starts with `await requireUserId(request)`, which
resolves the bearer token. The iOS app keeps the token in the Keychain; any 401 signs it out.

Google sign-in is written but **off until configured**: create an iOS OAuth client in Google
Cloud Console (bundle id `com.covera.app`), then set `COVERA_GOOGLE_CLIENT_ID` in
`ios/project.yml` and the same value as `GOOGLE_IOS_CLIENT_ID` in `api/.env`. The app uses the
native OAuth + PKCE flow (`Core/GoogleAuth.swift`, no SDK); the server verifies the ID token's
audience, issuer, expiry and verified email with Google.

`-CoveraDemo` (Debug builds only) loads the fictional sample plan and library from
`Core/PreviewData.swift` and skips the device lock, for screenshots and design review.
Sample data must obey the citation rule like real data does. `#if DEBUG` keeps all of it
out of release builds — keep it that way.

## Legal site

`site/` is a static site: Privacy Policy, Terms of Use, Consumer Health Data Privacy Policy
(Washington's My Health My Data Act) and Accessibility Statement (required in Israel). It must
describe what the code does — change it in the same commit as any change to collected data,
processors or retention. `site/check.sh` refuses to pass while a `[[BLANK]]` remains;
`site/check.sh --launch` also fails on pre-release statements. Preview with `covera-site` in
`.claude/launch.json`; deploy with `vercel deploy site --prod` after `vercel login`.

The app links to the pages via `Legal` (`Core/Legal.swift`, base URL from `CoveraLegalBaseURL`
in `project.yml`). Consent to health-data processing is explicit and versioned: bump
`Legal.version` when the policy changes in a way that needs fresh consent, and the server records
each account's consent (`POST /account/consent`, migration 005). Open items: `docs/LEGAL.md`.

## Design rules (iOS)

Black only — `preferredColorScheme(.dark)` plus `UIUserInterfaceStyle = Dark`. Colour means
exactly one thing each: blue = cited from a policy, amber = not stated / ask the insurer,
coral = deadline, conflict or withheld. **No green and no checkmarks anywhere**: nothing in
this app has been approved by an insurer. Serif (New York) for headings and verbatim quotes,
SF for everything else. All text colours are chosen to clear WCAG AA on `surface`.
`coveraLuxury()` (metal with a lit edge) is reserved for the one or two objects a screen is
about; everything else uses the flat `coveraCard()`, or the luxury stops reading as luxury.

Navigation: tabs are Home · Ask (cited chat, `POST /chat`) · Policies · Account. Language is
an in-app setting (English default; French, Spanish, Portuguese, Hebrew, Arabic, Hindi, Thai,
Japanese) in `Core/Localization.swift`; Hebrew and Arabic flip the layout right-to-left. Sheets
and full-screen covers do not inherit that direction — add `.coveraLayoutDirection()` to the
content of any new one. Format
dates with `.formatted(.coveraDate…)`, never `.dateTime`, or they ignore the setting. **After
adding or changing any user-facing string**, build, then run
`python3 ios/scripts/translate_strings.py <DerivedData>`: it fills only missing translations via
Gemini and rejects any that alter format specifiers, "Covera" or "DELETE". Server-sent error
messages are still English only. Guidance is deliberately *not* a tab — it is
a task, so it runs as a full-screen flow (`GuidanceFlow.swift`: one-tap intake → wait → plan)
presented from Home or a policy. `GuidanceModel` lives in `RootView`, so a closed plan can be
resumed from Home. Intake taps are sent as `answers`, never folded into prose.

## Environment gotcha

The AI key is `COVERA_GEMINI_API_KEY`, not `GEMINI_API_KEY`. Developer tools often export the
latter already, and Node's `--env-file` will not override an already-set variable — the `.env`
value would be silently ignored. One key covers generation and embeddings.

It must come from a project with **billing enabled**. On the Gemini API's unpaid tier Google may
use submitted content to improve its products, which breaks the promise in onboarding and
`docs/PRIVACY.md` that documents are never used for training.

## Phase status

- **Phase 0 — done.** Scaffolding, DB schema, storage, citation contract + verifier.
- **Phase 1 — code complete, partly unverified.** Ingestion pipeline, OCR fallback,
  chunking, embeddings, renewal diffing, upload route. PDF parsing, chunking,
  diffing, date handling, citation verification and route guards are tested. Originally
  written against Claude and Voyage, now ported to Gemini. Extraction and embeddings have run
  live on one fictional text PDF; the OCR path has never run (see weak points). A safety audit at the end of the phase
  found and fixed a separator bug that let a European-formatted `1.500` verify a claimed
  `1500`; see the git history of `verify.ts` before changing its numeric handling.
- **Phase 2 — works live on a fictional policy.** Retrieval (scoped by user,
  by `superseded_by IS NULL` and by page), plan assembly, the outbound citation gate, and
  `POST /guidance` which always carries the disclaimer so no client can render a plan
  without it. Same repair-loop contract as extraction: the verifier is the feedback signal.
- **Phase 3 — builds and runs.** SwiftUI client, Info.plist usage strings, privacy
  manifest, entitlements, asset catalogue, XcodeGen spec. Builds with zero warnings on
  Xcode 26.6 and runs on the iOS 26.5 simulator. The UI is a committed black design
  (see `Core/Theme.swift`); it has connected to the live API on the simulator via
  `-CoveraAccount`, but most screens have still been seen mainly with sample data. Never exercised at all: the camera
  scanner (the simulator has no camera) and "View the original" via Quick Look (needs the API).
- **Phase 4 — partly done.** `GET /account/export`, `DELETE /account`,
  `GET /documents/:id/file`, and the mechanical per-user isolation test. Sign-in
  (email/password; Google once configured) is done and tested live; Postgres RLS is still open.
- **Phase 5 — done for what exists.** Reduce Motion respected in `Theme.Motion`, RTL-safe
  bullets, Dynamic Type throughout, no success styling anywhere. Visually checked on the
  simulator at default text size only; large Dynamic Type sizes, VoiceOver and RTL
  (Hebrew) have not been run yet.
- **Phase 6 — documented, not submittable.** `docs/APP_STORE.md`, `docs/app-store/LISTING.md`
  (listing text, English and Hebrew), `docs/app-store/screenshots/` (6.9", regenerate with
  `-CoveraDemo -CoveraShot <screen>` and `ios/scripts/make_store_screenshots.swift`), app icon
  (`ios/scripts/make_app_icon.swift`), `docs/DEPLOY.md` (API not yet hosted). Blocked on a
  Developer Program account, hosting, and legal review.

## Known weak points

- **Authentication is basic.** No email verification and no password reset (both need an
  email provider). Rate limits are in Postgres (`auth/rate-limit.ts`, migration 006) and also cap
  the paid routes per account per day. Sessions slide while used; an hourly sweep in `server.ts`
  deletes expired sessions and guest accounts nobody can reach any more (`account/delete.ts`). **Sign in with Apple is required
  before App Store submission** once Google sign-in is offered (Guideline 4.8).
- **Hebrew policies.** Page text is rebuilt from positioned runs (`ingestion/pdf.ts`), since
  many Hebrew PDFs store no space characters. A fictional two-page Hebrew policy now extracts
  with every figure correct; a real insurer's Hebrew policy has not been re-tested since.
- **Live AI verified on one fictional policy only.** A made-up 2-page text PDF went through
  upload → Gemini extraction → verifier → embeddings → `/guidance` → `/chat`, with correct
  page citations and honest "not stated" answers. Still unexercised live: scanned PDFs (the OCR
  path), long real policies, non-English documents, renewal diffing. The first live calls found
  two Gemini-specific problems, both handled in `ai/gemini.ts`: zod's `const` is not enforced by
  Gemini (rewritten to a one-item `enum`), and the full policy schema is too large to enforce
  while decoding (400 "too many states"), so extraction sends it as instructions
  (`constrain: false`) and relies on zod and the verifier to reject bad output. Everything tested is
  the deterministic half: schemas, verifiers, diffing, dates, scoping.
- **Postgres RLS is still not enabled.** Isolation rests on `user_id` in every query, now
  enforced by `db/user-scope.test.ts`. RLS would move the guarantee into the database, but
  needs a per-request session role; the test is the interim guard, not a replacement.
- **OCR'd pages have a weaker guarantee.** For a scanned page, a citation is verified
  against our own transcription rather than the original, so the check is circular. Those
  pages are marked `ocr: true` and returned as `transcribed_pages`; the UI must not present
  them with the same confidence as text-layer pages.
- **The numeric check is unit-blind and digit-only.** `"80"` is supported equally by
  "80%", "80 days" or "₪80", and a value written in words ("ninety days", "covered in
  full") contains no digits to check, so it rests on the quote-on-page test alone.
  Tightening this needs unit-aware comparison.
- **Superseded policies keep live chunks.** `document_chunks` has no version linkage, so
  a replaced policy's text stays searchable. `guidance/retrieve.ts` joins `policies` and
  filters `superseded_by IS NULL` to compensate; any *new* retrieval path must do the same
  or expired caps will be quoted as current.
- **`findPreviousVersion` runs outside the write transaction.** Two concurrent uploads of
  the same renewal can fork one policy into two active groups.
- **Diffing is partial.** `diff.ts` does not compare `claims_process.steps`,
  `required_documents` or per-item `exclusions`, and drops the `ambiguous → not_stated`
  transition.
- **`document_pages` has no `user_id`.** Every read and write of it joins `documents` for
  ownership. The isolation test enforces this.
- **Deletion is not crash-safe.** `DELETE /account` removes blobs first, then rows, and
  refuses to delete rows if any blob delete failed. A crash between the two leaves rows
  pointing at missing files — recoverable, and the safer direction than orphaned health
  documents with nothing referencing them.

## Open decisions

- **AI provider — resolved: Gemini** for extraction, OCR, guidance and chat, replacing Claude.
  Embeddings are `gemini-embedding-001` at 768 dimensions (migration 003), replacing Voyage.
  Changing embedding model again means a migration and a full re-embed.
- **Legal positioning.** Paid insurance advice is licensed in many jurisdictions. Confirm
  positioning with a lawyer before commercial launch, and confirm local data-protection
  obligations for health data.
