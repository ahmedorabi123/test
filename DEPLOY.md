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
4. Save it — you'll paste it as `DATABASE_URL` in Render.

Free tier = 0.5 GB storage, suspends compute after 5 min idle but **data persists**.
First request after idle wakes in ~1s.

## 3) Provision Render backend

1. https://dashboard.render.com → **New +** → **Blueprint**.
2. Connect the GitHub repo. Render reads `backend/render.yaml` and proposes the service.
3. Click **Apply**. Then open the service → **Environment** and add the secrets that aren't in YAML:

| Key | Value |
|---|---|
| `RAILS_MASTER_KEY` | `6687fec84df3412bd0beec74532c7356` |
| `DATABASE_URL` | (Neon string from step 2) |
| `DEVISE_JWT_SECRET_KEY` | run `openssl rand -hex 64` locally and paste |
| `SHOPIFY_SHOP_DOMAIN` | `your-shop.myshopify.com` |
| `SHOPIFY_ADMIN_ACCESS_TOKEN` | `shpat_...` |
| `SHOPIFY_API_SECRET` | (from Shopify custom-app config) |
| `SHOPIFY_WEBHOOK_BASE_URL` | (set after first deploy — equals the Render URL, e.g. `https://shopify-erp-backend.onrender.com`) |
| `FRONTEND_ORIGIN` | (set after Vercel deploy — e.g. `https://your-app.vercel.app`) |
| `ADMIN_EMAIL` | `admin@erp.local` (or your own) |
| `ADMIN_PASSWORD` | strong password — this is what testers will use |

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

## 5) Backfill Shopify data into Neon (one-time)

This populates the live DB so testers see real products/customers/orders.
Run from Render's **Shell** tab (free plan supports shell):

```bash
bin/rails shopify:register_webhooks   # registers webhooks → Render URL

bin/rails runner '
client = Shopify::Client.new
products  = client.paginated("products.json",  key: "products")
customers = client.paginated("customers.json", key: "customers")
orders    = client.paginated("orders.json",    key: "orders", params: { status: "any" })
puts "Pulled #{products.size} products / #{customers.size} customers / #{orders.size} orders"
products.each  { |p| Catalog::ProductUpserter.call(p) }
customers.each { |c| CRM::CustomerUpserter.call(c) }
orders.each    { |o| Sales::OrderUpserter.call(o) }
'
```

Read-only mode (`READ_ONLY_SHOPIFY=true`) blocks any write back to Shopify — confirmed by 7 specs.
Webhook registration is whitelisted so it still works.

## 6) Hand to testers

URL: the Vercel link.
Credentials (one of):

| Role | Email | Password |
|---|---|---|
| admin | `admin@erp.local` | `changeme123!` (or your `ADMIN_PASSWORD` env override) |
| ops | `ops@erp.local` | `changeme123!` |
| accountant | `accountant@erp.local` | `changeme123!` |
| viewer | `viewer@erp.local` | `changeme123!` |

## 7) Iterating

```bash
# at your machine, after edits:
git add .
git commit -m "what changed"
git push
```

Both Render and Vercel auto-rebuild. Render also runs `db:migrate` automatically on every deploy — safe.

## 8) Reverting deployment-only choices later

| Knob | How to disable |
|---|---|
| Solid Queue in Puma | unset `SOLID_QUEUE_IN_PUMA` (production.rb falls back to Sidekiq if you re-enable Redis) |
| Read-only Shopify | unset / set `READ_ONLY_SHOPIFY=false` |
| Free Render → paid | upgrade plan only; no code change |
| Free Neon → managed PG | swap `DATABASE_URL` only |

No code paths are hard-coded to these — everything is env-driven.
