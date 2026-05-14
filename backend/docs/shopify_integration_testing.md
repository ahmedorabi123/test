# Shopify Integration — Real Setup Guide (Read-only)

> **This integration is one-way: Shopify → ERP.** The ERP only **reads**
> data from Shopify (via webhooks + REST pulls). It never writes orders,
> products, or inventory back to Shopify.

This guide tells you, step by step:

1. Which Shopify app to create (the right type matters — most people pick
   the wrong one and get stuck).
2. Every field you have to fill in on shopify.com (with the exact values).
3. Which scopes to enable.
4. How to get the credentials this codebase needs.
5. How to expose your local backend so Shopify can reach it.
6. How to register webhooks and verify everything works end-to-end.

---

## 1. Pick the right app type

Shopify has 3 app types. Use this:

| Want to…                                        | Use…                                   |
| ----------------------------------------------- | -------------------------------------- |
| Connect ONE store to this ERP (your case)       | **Custom app** (created in Admin)      |
| Sell the ERP on the App Store to many merchants | Public app (Partners dashboard, OAuth) |
| Internal-only app on a Plus / dev store         | Custom app via Partners dashboard      |

> **Use the "Custom app" path.** It avoids OAuth entirely. You get a single
> long-lived Admin API access token bound to one shop. That is all this
> codebase needs.
>
> If you tried this before with a Public/Partners app and "it didn't work",
> the most common reason is that you got OAuth tokens but never installed
> the app on a real shop, or the redirect URLs didn't match. **Skip OAuth
> entirely and use a Custom app.**

---

## 2. Create the Custom app in Shopify Admin

> Requires the **Develop apps** permission on the store. If you don't see
> "Develop apps" under _Settings → Apps and sales channels_, an account
> owner has to enable it once: Settings → Apps and sales channels → Develop
> apps → **Allow custom app development**.

### 2.1 Step-by-step (every screen, every field)

1. Go to your shop: `https://<your-shop>.myshopify.com/admin`.
2. **Settings** (bottom-left) → **Apps and sales channels**.
3. Click **Develop apps** (top-right).
4. Click **Create an app**.

   | Field         | Value                                              |
   | ------------- | -------------------------------------------------- |
   | App name      | `ERP Sync` (anything you want — it's local to you) |
   | App developer | Pick yourself                                      |

5. Click **Create app**.

6. On the new app page, click **Configuration** (tab).
   - **Admin API integration** → click **Configure**.
   - **Admin API access scopes** → enable the scopes in §3 below.
   - **Webhook subscriptions** section: leave version **2025-01** (matches
     `SHOPIFY_API_VERSION` default in this repo). Don't add webhooks here —
     we register them programmatically (§6).
   - **Storefront API integration**: skip. Not used.
   - **Event version**: leave default.
   - Click **Save**.

7. Click **API credentials** (tab) → **Install app** → **Install**.

   This generates the credentials. Now you can read them:
   - **Admin API access token** — starts with `shpat_…`. Click **Reveal token
     once** and copy it immediately (you can only see it ONCE; if you lose
     it you have to uninstall + reinstall).
   - **API key** — public-ish, not used by this read-only flow.
   - **API secret key** — used to verify webhook HMAC signatures.

You now have the three things this app needs:

| Need                         | Where it comes from                              |
| ---------------------------- | ------------------------------------------------ |
| `SHOPIFY_SHOP_DOMAIN`        | The `<your-shop>.myshopify.com` part of your URL |
| `SHOPIFY_ADMIN_ACCESS_TOKEN` | "Admin API access token" — `shpat_…`             |
| `SHOPIFY_API_SECRET`         | "API secret key" on the API credentials tab      |

### 2.2 What you do NOT need to fill in

For a **Custom app** there is no:

- App URL
- Allowed redirection URL(s)
- Client ID / Client secret screen
- OAuth consent flow

Those are only used for **Public** apps (App Store distribution). If a
form on shopify.com is asking you for those, you opened the Partners
dashboard by mistake — go back to _Admin → Settings → Apps and sales
channels → Develop apps_.

---

## 3. Scopes to enable (READ-ONLY)

On the **Configuration → Admin API access scopes** screen, tick **only**
these (uncheck everything else):

- `read_products`
- `read_product_listings`
- `read_inventory`
- `read_orders`
- `read_all_orders` _(needed to read orders > 60 days old; Shopify shows
  a "Request access" button — click it; auto-approved for custom apps)_
- `read_customers`
- `read_fulfillments`
- `read_shipping`
- `read_locations`
- `read_price_rules`
- `read_discounts`

> **Do NOT enable any `write_*` scope.** This codebase has no outbound
> writes; granting write scopes only widens your blast radius if the token
> ever leaks.

Click **Save** at the bottom. If you change scopes later, you must
**uninstall + reinstall** the app to mint a new token with the new scopes.

---

## 4. Expose your local backend (so Shopify can reach it)

Shopify's webhook delivery service has to POST to a public HTTPS URL.
Your laptop on `localhost:3010` won't work. Two equally good options:

### Option A — Cloudflare tunnel (recommended, free, no signup)

```bash
brew install cloudflared
cloudflared tunnel --url http://localhost:3010
```

Cloudflared prints a line like:

```
Your quick tunnel: https://shiny-words-rule-fast.trycloudflare.com
```

Copy that URL. That is your `WEBHOOK_BASE_URL`.

### Option B — ngrok

```bash
brew install ngrok
ngrok http 3010
```

Copy the `https://….ngrok-free.app` URL. That is your `WEBHOOK_BASE_URL`.

> Keep the tunnel running in its own terminal. If you close it, the URL
> changes and you have to re-run `rake shopify:register_webhooks`.

---

## 5. Wire the credentials into the backend

Create / edit `backend/.env` (or set these in your shell before
`docker compose up`):

```bash
# ── Shopify connection ─────────────────────────────────────────
SHOPIFY_SHOP_DOMAIN=your-shop.myshopify.com
SHOPIFY_ADMIN_ACCESS_TOKEN=shpat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SHOPIFY_API_SECRET=shpss_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SHOPIFY_API_VERSION=2025-01

# ── Public URL Shopify will POST webhooks to ───────────────────
WEBHOOK_BASE_URL=https://shiny-words-rule-fast.trycloudflare.com

# ── Local-only safety valve. NEVER set in production. ──────────
# WEBHOOKS_HMAC_BYPASS=true
```

Restart the backend so the new env vars are picked up:

```bash
docker compose -f backend/docker-compose.yml up -d --force-recreate backend
```

> **Variable names matter — these are the exact names the code reads:**
> `SHOPIFY_ADMIN_ACCESS_TOKEN` (not `SHOPIFY_ACCESS_TOKEN`),
> `WEBHOOK_BASE_URL` (singular, not `WEBHOOKS_BASE_URL`).
> If you mistype, the rake task aborts with "WEBHOOK_BASE_URL not set".

### 5.1 Smoke-test the credentials before registering webhooks

```bash
docker compose -f backend/docker-compose.yml exec backend \
  bundle exec rails runner 'pp Integrations::Shopify::Client.new.get("shop.json")'
```

You should see your shop's name, email, plan, etc. If you get a 401 the
token is wrong or the app isn't installed; if you get a 404 the shop
domain is wrong.

---

## 6. Register webhooks (one command)

```bash
docker compose -f backend/docker-compose.yml exec backend \
  bundle exec rake shopify:register_webhooks
```

Expected output:

```
+  orders/create              -> https://….trycloudflare.com/webhooks/shopify/orders/create
+  orders/updated             -> ...
+  orders/paid                -> ...
+  orders/cancelled           -> ...
+  orders/fulfilled           -> ...
+  refunds/create             -> ...
+  products/create            -> ...
+  products/update            -> ...
+  inventory_levels/update    -> ...
+  customers/create           -> ...
+  customers/update           -> ...
+  fulfillments/create        -> ...
+  fulfillments/update        -> ...
```

Verify they're live in Shopify:

```bash
docker compose -f backend/docker-compose.yml exec backend \
  bundle exec rake shopify:list_webhooks
```

Or in Shopify Admin: _Settings → Notifications → Webhooks_ (scroll down).

---

## 7. End-to-end verification scenarios

In every scenario, watch your backend log:

```bash
docker compose -f backend/docker-compose.yml logs -f backend
```

### 7.1 Product create → ERP product

1. In Shopify Admin: Products → **Add product**, set title `Test Tee`,
   one variant, $19.99, **Save**.
2. Within ~5 seconds the backend log shows
   `Started POST /webhooks/shopify/products/create` followed by
   `[ProcessShopifyWebhookJob] processed`.
3. ERP UI: `/products` shows `Test Tee`.

### 7.2 Order create → ERP order

1. In Shopify Admin: Orders → **Create order** → add a line item, **Mark
   as paid** with Bogus Gateway, **Create order**.
2. Backend log shows `orders/create` then `orders/paid` deliveries.
3. ERP UI: `/orders` shows the new order, source=`shopify`,
   financial_status=`paid`. Accounting → Journal Entries has a new entry
   for it.

### 7.3 Fulfillment → stock movement

1. In Shopify Admin: open the order → **Mark as fulfilled**.
2. Backend log shows `fulfillments/create`.
3. ERP UI: Inventory → Movements has a row with reason=`fulfilled` and
   negative delta against the matching variant. The warehouse will be
   `SHOPIFY-<location_id>` (auto-created the first time).

### 7.4 Refund → reversal journal

1. In Shopify Admin: refund the order.
2. Backend log shows `refunds/create`.
3. ERP order: `financial_status` becomes `refunded` (or `partially_refunded`
   on a partial refund). A contra journal entry appears in Accounting.

### 7.5 Inventory adjusted in Shopify

1. In Shopify Admin: Products → variant → adjust inventory at any
   location.
2. Backend log shows `inventory_levels/update`.
3. ERP `StockItem.quantity_on_hand` updates and a `StockMovement` row
   is recorded.

---

## 8. Replay a webhook locally (no Shopify Admin needed)

Every inbound webhook is persisted to `webhook_events` before it's
processed, so you can re-run any of them:

```bash
docker compose -f backend/docker-compose.yml exec backend bundle exec rails console
```

```ruby
last = WebhookEvent.order(created_at: :desc).first
Shopify::ProcessWebhookJob.perform_now(last.id)
```

To synthesize a fake delivery without using Shopify at all (dev only):

```bash
WEBHOOKS_HMAC_BYPASS=true \
docker compose -f backend/docker-compose.yml up -d --force-recreate backend

curl -X POST http://localhost:3010/webhooks/shopify/orders/create \
     -H 'X-Shopify-Topic: orders/create' \
     -H 'X-Shopify-Shop-Domain: test.myshopify.com' \
     -H 'X-Shopify-Webhook-Id: dev-1' \
     -H 'Content-Type: application/json' \
     -d '{"id":9001,"name":"#1001","total_price":"50.00","currency":"USD","line_items":[]}'
```

> **Never set `WEBHOOKS_HMAC_BYPASS=true` outside development.**

---

## 9. Troubleshooting (the things that bite people)

| Symptom                                                  | Fix                                                                                                                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WEBHOOK_BASE_URL not set`                               | You set `WEBHOOKS_BASE_URL` (plural). It's `WEBHOOK_BASE_URL` (singular).                                                                                                                      |
| `401 Unauthorized` from `shop.json` smoke test           | Token is wrong, or you copied the **API key** instead of the **Admin API access token**. The token always starts with `shpat_`.                                                                |
| Webhooks register fine but never fire                    | Cloudflared / ngrok tunnel died — the URL Shopify has is now dead. Restart the tunnel, update `WEBHOOK_BASE_URL`, re-run `rake shopify:register_webhooks` (it deletes + recreates stale ones). |
| HMAC verification fails on every webhook                 | `SHOPIFY_API_SECRET` is wrong. It's the **API secret key** on the _API credentials_ tab, not the access token.                                                                                 |
| `read_all_orders` scope denied                           | Click "Request access" on the scope row in Shopify; for custom apps it auto-approves. Then **uninstall + reinstall** the app to mint a new token.                                              |
| Webhook arrives but order doesn't appear in ERP          | Check `WebhookEvent.last.processing_error`. Common cause: a referenced variant isn't in the ERP yet — backfill products first (§10).                                                           |
| Changing scopes had no effect                            | You must uninstall + reinstall the app for new scopes to take effect on the existing token.                                                                                                    |
| Shopify Admin asked you for "App URL" or "Redirect URLs" | You opened the **Partners** dashboard, not Admin. Go to _Admin → Settings → Apps and sales channels → Develop apps_. Custom apps don't need those.                                             |

---

## 10. Initial backfill (recommended before going live)

Webhooks only deliver future events. To populate the ERP with what's
already in your shop, run a one-shot Rails console pull:

```bash
docker compose -f backend/docker-compose.yml exec backend bundle exec rails console
```

```ruby
client = Integrations::Shopify::Client.new

# Products
client.paginated("products.json", key: "products").each do |p|
  Catalog::Shopify::ProductUpserter.call(p)
end

# Customers
client.paginated("customers.json", key: "customers").each do |c|
  Crm::Shopify::CustomerUpserter.call(c)
end

# Orders (status=any pulls open + closed + cancelled)
client.paginated("orders.json", key: "orders", params: { status: "any" }).each do |o|
  Sales::Shopify::OrderUpserter.call(o)
end
```

> If `Integrations::Shopify::Client#paginated` doesn't exist yet, add a
> follow-up to implement cursor-based (`Link: <…>; rel="next"`)
> pagination — Shopify's REST returns 250 max per page.

---

## 11. Going to production

1. Create a separate Custom app on the **production** store, not the dev
   store. (Tokens are not portable across shops.)
2. Use a stable URL — the production backend's public hostname — as
   `WEBHOOK_BASE_URL`. No tunnels in prod.
3. Set the env vars in your prod orchestrator (Kamal, Render, Fly, etc.).
4. Run `rake shopify:register_webhooks` against production once.
5. Run the backfill snippet (§10) once.
6. Run scenarios 7.1 → 7.4 with one low-value real order.

---

## 12. What is intentionally NOT supported

- Outbound writes to Shopify (no order creation, no inventory push, no
  product mutations). This is by design while you stabilize the read
  path.
- OAuth / Public app distribution. Add a separate
  `app/domains/integrations/services/shopify/oauth/…` module later if you
  ever need to support multiple merchant installs.
- GraphQL Admin API. The codebase uses REST today; the switch is
  mechanical but unnecessary while scopes stay read-only.
