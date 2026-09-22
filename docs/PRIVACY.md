# Privacy policy

The privacy policy now lives in `site/privacy.html`, with the Terms of Use, the
Consumer Health Data Privacy Policy and the Accessibility Statement beside it.
Those pages are what users and App Review see; this file only points to them.

Keep them true to the code. When a data type, a processor or a retention period
changes, change `site/` in the same commit, bump `Legal.version` in
`ios/Covera/Core/Legal.swift` if users must consent again, and update
`ios/Covera/PrivacyInfo.xcprivacy` and the App Store privacy label to match.

Open legal work is tracked in `docs/LEGAL.md`.
