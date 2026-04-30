# Live deployment runbook

Stack: **Neon Postgres (free) + Render web service (free) + Vercel (free)**.
GitHub-driven: every `git push origin main` redeploys both Render and Vercel.

> Master key for this app (paste into Render as `RAILS_MASTER_KEY`):
> `6687fec84df3412bd0beec74532c7356`
> (Stored locally in `backend/config/master.key` — gitignored. Do not share publicly.)

---

## 1) Push the repo to GitHub

```bash
cd /Users/ahmedorabi/Desktop/shopify_erp_2
git add .
git commit -m "Initial commit — ready for live deployment"

# Create an empty repo on github.com (no README, no .gitignore), then:
git remote add origin git@github.com:<your-user>/<repo-name>.git
git push -u origin main
```

## 2) Provision Neon Postgres (free tier, persistent — no auto-sleep data loss)

1. Sign up at https://neon.tech.
2. Create project → region close to Render (e.g. `us-east-1`).
3. Copy the **pooled** connection string. It looks like:
   `postgresql://user:pwd@ep-xxx-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require`
   postgresql://neondb_owner:npg_z1yqxS6OjvhD@ep-delicate-meadow-anqrcqs2.c-6.us-east-1.aws.neon.tech/neondb?sslmode=require
4. Save it — you'll paste it as `DATABASE_URL` in Render.

Free tier = 0.5 GB storage, suspends compute after 5 min idle but **data persists**.
First request after idle wakes in ~1s.

## 3) Provision Render backend

1. https://dashboard.render.com → **New +** → **Blueprint**.
2. Connect the GitHub repo. Render reads `backend/render.yaml` and proposes the service.
3. Click **Apply**. Then open the service → **Environment** and add the secrets that aren't in YAML:

| Key                          | Value                                                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------- |
| `RAILS_MASTER_KEY`           | `6687fec84df3412bd0beec74532c7356`                                                                |
| `DATABASE_URL`               | (Neon string from step 2)                                                                         |
| `DEVISE_JWT_SECRET_KEY`      | run `openssl rand -hex 64` locally and paste                                                      |
| `SHOPIFY_SHOP_DOMAIN`        | `your-shop.myshopify.com`                                                                         |
| `SHOPIFY_ADMIN_ACCESS_TOKEN` | `shpat_...`                                                                                       |
| `SHOPIFY_API_SECRET`         | (from Shopify custom-app config)                                                                  |
| `SHOPIFY_WEBHOOK_BASE_URL`   | (set after first deploy — equals the Render URL, e.g. `https://shopify-erp-backend.onrender.com`) |
| `FRONTEND_ORIGIN`            | (set after Vercel deploy — e.g. `https://your-app.vercel.app`)                                    |
| `ADMIN_EMAIL`                | `admin@erp.local` (or your own)                                                                   |
| `ADMIN_PASSWORD`             | strong password — this is what testers will use                                                   |

4. Click **Manual Deploy** → **Deploy latest commit**. Build takes ~5 min.
5. The start command runs `db:migrate && db:seed` automatically — this creates the `admin/ops/accountant/viewer` users in Neon.
6. Once green, copy the service URL and paste it back into the env as `SHOPIFY_WEBHOOK_BASE_URL`.

## 4) Provision Vercel frontend

1. https://vercel.com/new → import the same GitHub repo.
2. **Root Directory** = `frontend`. Framework auto-detects Vite (also defined in `frontend/vercel.json`).
3. Add env var:
   - `VITE_API_URL` = `https://shopify-erp-backend.onrender.com` (the Render URL, no trailing slash)
4. Click **Deploy**.
5. Copy the resulting `https://<app>.vercel.app` URL and paste it back into Render env as `FRONTEND_ORIGIN` → trigger Render redeploy from the dashboard.

## 5) Shopify data: persistent, auto-loaded, kept live

Neon = persistent Postgres (data survives forever, even when Render's web
dyno sleeps). The `bootstrap:run` rake task runs on every deploy and is
**self-deciding**:

- **First deploy** — DB has no Shopify rows → backfill runs:
  paginates **all** products, customers, orders from your Shopify store and
  upserts them into Neon.
- **All subsequent deploys** — DB already has Shopify data → backfill is
  **skipped** ("DB already has Shopify data … skipping backfill"). Webhooks
  re-register every deploy and keep Neon in sync continuously.
- **Force a re-pull** — set `FORCE_BACKFILL=true` in Render env and redeploy.
  Remove the var afterwards.

No manual action needed. Just make sure these env vars are set on Render:

- `SHOPIFY_SHOP_DOMAIN`, `SHOPIFY_ADMIN_ACCESS_TOKEN`
- `SHOPIFY_WEBHOOK_BASE_URL` = your Render URL
- `READ_ONLY_SHOPIFY=true` (already in `render.yaml` — blocks any write back to your store)

Watch the **Logs** tab during deploy. Expected first-deploy output:

```
[bootstrap] Registering webhooks against https://shopify-erp-backend.onrender.com ...
+  products/create  -> https://shopify-erp-backend.onrender.com/webhooks/shopify/products/create
... (one line per webhook topic)
[bootstrap] DB empty of Shopify data — running first-time backfill
[bootstrap] Pulling products ...
[bootstrap]   fetched 213; upserting...
[bootstrap] Pulling customers ...
[bootstrap]   fetched 87; upserting...
[bootstrap] Pulling orders (status=any) ...
[bootstrap]   fetched 456; upserting...
[bootstrap] Done. Products=213 Customers=87 Orders=456
```

Expected output on every later deploy:

```
[bootstrap] Registering webhooks against https://shopify-erp-backend.onrender.com ...
=  products/create  (already registered)
... (no-op for each topic)
[bootstrap] DB already has Shopify data (products=213, orders=456). Skipping backfill — webhooks will keep it in sync. Set FORCE_BACKFILL=true to re-pull everything.
```

> **How the integration stays live:** Shopify pushes change events (product
> updated, order created, inventory level changed, refund created, …) to
> `https://<render>.onrender.com/webhooks/shopify/<topic>`. The handlers run
> the same upserter classes the backfill uses, so the DB stays current
> without polling. Re-registration on every deploy is what keeps the webhook
> URLs pointing at the latest Render service.

## 6) Hand to testers

URL: the Vercel link.
Credentials (one of):

| Role       | Email                  | Password                                               |
| ---------- | ---------------------- | ------------------------------------------------------ |
| admin      | `admin@erp.local`      | `changeme123!` (or your `ADMIN_PASSWORD` env override) |
| ops        | `ops@erp.local`        | `changeme123!`                                         |
| accountant | `accountant@erp.local` | `changeme123!`                                         |
| viewer     | `viewer@erp.local`     | `changeme123!`                                         |

## 7) Iterating

```bash
# at your machine, after edits:
git add .
git commit -m "what changed"
git push
```

Both Render and Vercel auto-rebuild. Render also runs `db:migrate` automatically on every deploy — safe.

## 8) Reverting deployment-only choices later

| Knob                   | How to disable                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| Solid Queue in Puma    | unset `SOLID_QUEUE_IN_PUMA` (production.rb falls back to Sidekiq if you re-enable Redis) |
| Read-only Shopify      | unset / set `READ_ONLY_SHOPIFY=false`                                                    |
| Free Render → paid     | upgrade plan only; no code change                                                        |
| Free Neon → managed PG | swap `DATABASE_URL` only                                                                 |

No code paths are hard-coded to these — everything is env-driven.
