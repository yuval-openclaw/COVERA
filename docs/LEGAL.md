# Legal readiness

Not legal advice. This is the list an Israeli privacy and insurance-regulation
lawyer should review, ordered by how likely each item is to cause a claim, a
fine or a rejection. The legal pages are in `site/`; `site/check.sh` gates
publishing and `site/check.sh --launch` gates release.

## Done in the repo

- Privacy Policy, Terms of Use, Consumer Health Data Privacy Policy and
  Accessibility Statement, written against what the code does (`site/`).
- After sign-in, before anything else, three separate off-by-default
  agreements (`ConsentView`): the Terms of Use with 18+ confirmation (makes the
  liability limits enforceable), consent to health-data processing (kept
  separate, as the GDPR requires), and acknowledgment that Covera is not advice.
  Shown again whenever `Legal.version` changes.
- The server refuses uploads, plans and chat from any account without all
  three on record (`requireConsent`), so no old or modified client can skip it.
- Proof: each agreement is stored with its own time and the version agreed to
  (migrations 005 and 007, `POST /account/consent`), and appears in the user's
  export.
- In-app links to the Privacy Policy and Terms (onboarding and Account), as App
  Review requires. They previously pointed at `covera.app`, a domain not owned.
- Policy text kept out of server logs (a rejected-extraction log line leaked
  quotes; fixed, and the leaked lines removed from the local log).
- Emergency first: choosing "Emergency" shows a call-for-help card with the
  region's number (101 in Israel) above any insurance step, and on the plan.
- Abuse and cost limits kept in Postgres (survive restarts): sign-in attempts,
  5 guest accounts per address per hour, and daily caps per account on uploads
  (20), plans (30) and chat (150). Keys are hashed, so no emails or IPs stored.
- Uploads must really be PDFs (checked by content, not the declared type).
- Retention matches the policy: expired sessions and rate-limit rows are swept
  hourly; sessions renew while used; guest accounts no one can reach any more
  (no live session for 30 days) are deleted with all their files.
- Site security headers (CSP, HSTS, no framing, no referrer).

## Published

Live at https://covera-legal.vercel.app (Vercel project `covera-legal`), owner
Eyal Baruch, contact covera.privacy@gmail.com. Redeploy after any change with
`cd site && ./check.sh && vercel deploy --prod`. For App Store Connect, the
Privacy Policy URL is https://covera-legal.vercel.app/privacy.html.

## Before release — highest risk first

1. **Insurance licensing (Israel).** Explaining what a policy covers and
   suggesting steps may be treated as insurance advice or agency under the
   Control of Financial Services (Insurance) Law. Get a written opinion before
   launch, and before charging anything.
2. **Operate through a company.** As a private individual, a judgment can reach
   personal assets. Incorporate, then replace the owner name in `site/`. Add
   professional liability and cyber insurance.
3. **Trademark.** "Covera Health" is an existing US health-technology company.
   Run a trademark search in Israel, the EU and the US before investing in the
   name.
4. **Gemini paid tier.** The policy promises documents are not used for
   training. That is true only on a billing-enabled Gemini project; confirm it,
   accept Google's data processing terms, and rotate the key that was pasted
   into a chat.
5. **Washington My Health My Data Act.** Private right of action, no size
   threshold. Separate health-data policy and prior consent are done; keep the
   home page link to it, never share health data without separate consent, and
   answer requests within 45 days.
6. **GDPR / UK GDPR.** Appoint EU and UK Article 27 representatives, write a
   Data Protection Impact Assessment (large-scale health data), keep a record of
   processing, and replace the pre-release statements (`./check.sh --launch`).
7. **Israel Privacy Protection Law, Amendment 13 and the Data Security
   Regulations.** Health data puts the database at a higher security level:
   written security procedures, access control and logging, periodic review,
   breach reporting to the Privacy Protection Authority. Check whether a Data
   Protection Officer is required at your scale.
8. **Name the hosting provider and region** once the API is deployed, set log
   retention to 30 days and backup retention to 30 days to match the policy.
9. **Security gaps the policy does not paper over.** No email verification, no
   password reset, in-memory login rate limit, Postgres RLS not enabled (see
   CLAUDE.md → Known weak points).
10. **App Store.** Sign in with Apple is built, but untested until the
    Developer account exists (the entitlement needs a team). Privacy label matching `PrivacyInfo.xcprivacy`, Medical-category review
    notes (see `docs/APP_STORE.md`).
11. **Hebrew versions** of the Privacy Policy and Terms for Israeli users.
