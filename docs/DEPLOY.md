# Deploying the API

The app cannot reach a server on a laptop. Before release the API needs three
hosted pieces. Pick a region in the EU (for example Frankfurt): Israel and the EU
recognise each other's data protection, and it keeps GDPR transfers simple.

| Piece | Needs | Examples |
| --- | --- | --- |
| API | runs `api/Dockerfile`, HTTPS, a proxy in front | Railway, Render, Fly.io |
| Database | Postgres 17 **with pgvector** | Neon, Supabase, Railway Postgres |
| File storage | S3-compatible bucket, private | Cloudflare R2, AWS S3 |

Local disk storage is not an option in production: a container's disk is wiped
on every deploy, and the documents with it.

## Environment

| Variable | Value |
| --- | --- |
| `NODE_ENV` | `production` |
| `DATABASE_URL` | from the database provider (require SSL) |
| `STORAGE_DRIVER` | `s3` |
| `S3_BUCKET`, `S3_REGION` | the bucket; region `auto` for R2 |
| `S3_ENDPOINT` | only for S3-compatible storage, e.g. R2's account endpoint |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | a key limited to that one bucket |
| `DOCUMENT_ENCRYPTION_KEY` | a **new** 64-character hex key: `openssl rand -hex 32`. Keep a copy somewhere safe — without it every stored document is unreadable |
| `COVERA_GEMINI_API_KEY` | a key from a Google Cloud project **with billing enabled** (see CLAUDE.md), not the key that was pasted in chat |
| `TRUST_PROXY` | `1` — the number of proxies in front (Fly.io is one hop). Not `true`: a bare boolean lets a client forge X-Forwarded-For and evade rate limits. `false` only with no proxy |
| `GOOGLE_IOS_CLIENT_ID` | only when Google sign-in is set up |

`HOST` and `PORT` are set by the image.

## Steps

1. Create the database, then run migrations once against it:
   `docker run --env-file prod.env covera-api node dist/db/migrate.js`
   (or, without Docker: `cd api && npm run build && node --env-file=prod.env dist/db/migrate.js`).
2. Create the bucket, private, with a key that can only reach it.
3. Deploy `api/` with the variables above. Check `https://<your-api>/health`
   returns `{"status":"ok"}`.
4. Put the API address in `ios/project.yml` under `configs → Release →
   CoveraAPIBaseURL`, run `xcodegen generate`, and archive.
5. Name the hosting provider and region in `site/privacy.html` and
   `site/health-data.html` (replace the pre-release statements), run
   `site/check.sh --launch`, and redeploy the site.
6. Set log retention to 30 days and backup retention to 30 days at the
   provider, as the privacy policy states.
7. Create the App Review demo account on this server and upload fictional
   policies to it (see `docs/app-store/LISTING.md`).
