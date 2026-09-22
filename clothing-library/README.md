# ספריית בגדים · Clothing Library

Photograph a clothing item and find out which household member it belongs to. The app
compares micro-features (size label, tears, stains, fading, stretched elastic) against the
household's saved items.

```
npm install
cp .env.example .env.local   # add CLOTHING_GEMINI_API_KEY for real identification
npm run dev                  # http://localhost:3100
```

Without a key the app runs in **demo mode**: the scan flow works end to end, but the result is
simulated, and every demo result is labeled that way on screen.

## How it works

- **Entry** (`app/page.tsx`): sign in, sign up, continue as a guest, or enter an access code.
  Every account gets a unique code (`CL-XXXX-XXXX`) that reopens its library from any device.
- **Code prompt** (`components/AccessCodeModal.tsx`): asks the user to copy the code. If they
  skip it, it asks once more with stronger wording. If they skip again, it never shows again
  (stored per user in localStorage). The code is always available from the ⋯ menu.
- **Library** (`app/library/page.tsx`): items grouped by person, with filters by person and by
  item type. New accounts start empty: add household members, then scan and save their items.
- **Scan** (`components/ScanFlow.tsx`): live camera (`getUserMedia`) or upload. Images are
  resized on the device to 1024px before upload. After a scan the user can save the item to
  anyone's library, and saved photos improve later matches.
- **Vision** (`lib/vision.ts`): sends Gemini the new photo, the text of every library item, and
  up to 16 reference photos, and gets structured JSON back. The app names an owner only when
  confidence is at least 0.6; below that it says it isn't sure. The model is told that
  matching color and garment type alone is not a match.

## Mock database

`lib/db.ts` stores everything in `data/db.json` (git-ignored) and creates it on first run:
`users` · `sessions` · `people` · `items`. Every library query is scoped to the owner's id.
Passwords are stored as scrypt hashes, and sessions as SHA-256 hashes of a random token kept in
an httpOnly cookie. To use a real database, replace this module; the routes only call its
exported functions.

## Not production-ready

- The JSON file store is single-process. Use Postgres or similar before deploying.
- Login throttling is in memory.
- There is no email verification or password reset.
