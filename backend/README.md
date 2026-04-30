# Shopify ERP — Backend

Rails 8.0.5 API-only service backing the ERP console. Ingests Shopify webhooks,
drives the React frontend via JWT-authenticated endpoints, and projects orders,
inventory, fulfillments, refunds, and accounting.

## Quick start — UI-ready in one command

Run from the repository root:

```bash
# 1. Backend stack (Postgres, Redis, OpenSearch, Rails, Sidekiq)
docker compose -f backend/docker-compose.yml up -d

# 2. Prepare + seed the database (only needed once, or after resets)
docker compose -f backend/docker-compose.yml exec backend bin/rails db:prepare db:seed

# 3. Frontend (Vite dev server)
docker compose -f frontend/docker-compose.yml --project-directory frontend up -d
```

Open <http://localhost:5174> and log in.

## Test credentials (seeded)

All users share password `changeme123!`:

| Email                | Role       |
| -------------------- | ---------- |
| admin@erp.local      | Admin      |
| ops@erp.local        | Operations |
| viewer@erp.local     | Viewer     |
| accountant@erp.local | Accountant |

## Ports

| Service    | URL                     |
| ---------- | ----------------------- |
| Frontend   | <http://localhost:5174> |
| Rails API  | <http://localhost:3010> |
| Postgres   | localhost:54321         |
| Redis      | localhost:63791         |
| OpenSearch | <http://localhost:9202> |

## UI surfaces ready for browser testing

- **Dashboard** — 30-day revenue, orders by status, low-stock snapshot.
- **Products** — CRUD.
- **Orders** — list, detail drawer (line items + shipments + refunds),
  `+ New order` button for manual/showroom orders.
- **Customers** — list + recent-orders expansion.
- **Shipments** — read-only view of fulfillments (Bosta, UPS, DHL …).
- **Refunds** — read-only view with partial/full flag.
- **Inventory** — warehouses + stock items + adjust.
- **Accounting** — trial balance, P&L, journal entries.

## Environment variables

Set in the backend's `.env` (docker-compose loads it).

```
# Devise/JWT
DEVISE_JWT_SECRET_KEY=<openssl rand -hex 64>

# Shopify
SHOPIFY_SHOP_DOMAIN=<my-store>.myshopify.com
SHOPIFY_ADMIN_ACCESS_TOKEN=shpat_...
SHOPIFY_API_VERSION=2025-01
SHOPIFY_WEBHOOK_SECRET=<HMAC secret from the Shopify app>
WEBHOOK_BASE_URL=https://<tunnel>.trycloudflare.com   # for webhook registration

# Bosta (when BOSTA_DIRECT_ENABLED=true the adapter will call the real API,
# otherwise it stays a stub and Bosta data arrives via the Shopify
# "Bosta" tracking_company on fulfillments webhooks).
BOSTA_DIRECT_ENABLED=false
BOSTA_API_KEY=
BOSTA_API_BASE=https://app.bosta.co/api/v2

# Seed overrides (optional)
ADMIN_EMAIL=admin@erp.local
ADMIN_PASSWORD=changeme123!
```

## Shopify webhooks

Register all supported topics against your tunnel once:

```bash
WEBHOOK_BASE_URL=https://<tunnel>.trycloudflare.com \
  docker compose -f backend/docker-compose.yml exec backend bin/rails shopify:register_webhooks
```

Topics handled (see `Shopify::EventNormalizer::SUPPORTED_TOPICS`):

- `orders/create`, `orders/updated`, `orders/paid`, `orders/cancelled`, `orders/fulfilled`
- `refunds/create`
- `fulfillments/create`, `fulfillments/update`
- `customers/create`, `customers/update`
- `products/create`, `products/update`
- `inventory_levels/update`

Idempotency is enforced by the `webhook_events (source, external_id)` unique
index, so replays are safe.

## Bosta integration (current model)

Fulfillments delivered by Bosta arrive through Shopify's `fulfillments/*`
webhooks with `tracking_company: "Bosta"`. `Shipping::Shopify::FulfillmentUpserter`:

1. persists the fulfillment + line items,
2. captures tracking_number + tracking_url for UI display,
3. deducts inventory exactly once (row-locked via `Inventory::WriteMovement`).

To push/pull directly from Bosta, flip `BOSTA_DIRECT_ENABLED=true` and fill in
`app/domains/shipping/services/shipping/adapters/bosta_adapter.rb`. The UI and
accounting already consume the `carrier = "bosta"` projection.

## Estebdal (exchanges) — current model

Shopify represents exchanges as `refund → new order`. `Sales::Shopify::RefundUpserter`:

- creates the `Refund` + `RefundLineItem` rows,
- restocks inventory when `restock_type ∈ {"return", "cancel"}`,
- posts `Accounting::PartialRefundJournalHandler` (tax-proportional) for
  partial refunds and reverses the original sale journal on a full refund.

Exchange linkage is carried on the Shopify order tag
`estebdal_exchange_of:<order_id>` (read by `OrderUpserter`).

## Running tests

```bash
docker compose -f backend/docker-compose.yml exec backend bin/rails db:test:prepare
docker compose -f backend/docker-compose.yml exec backend bundle exec rspec
```

Current status: **232/232 green**.

# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions

- ...

---

## Never lose your dev data (and debug login 401s fast)

### Why data persists across restarts
Postgres and Redis both live on **named Docker volumes** (`postgres_data`, `redis_data`). These survive:

- `docker compose stop`
- `docker compose down` (without flags)
- `docker compose restart`
- Host reboot

They are **destroyed only** by `docker compose down -v` or `docker volume rm`.

### If login suddenly returns 401
The API now returns a `code` field so you can see exactly what's wrong:

| `error.code`      | Meaning                                        | Fix                                                |
|-------------------|------------------------------------------------|----------------------------------------------------|
| `no_user`         | Email doesn't exist in DB                      | Run `bin/rails db:seed`                            |
| `wrong_password`  | User exists but password hash mismatches       | Check `ADMIN_PASSWORD` env, re-seed                |
| `inactive`        | User record has `active = false`               | `User.find_by(...).update!(active: true)`          |

Every failure is also written to `audit_logs` (action `auth.login.failed`, diff `{email, reason}`).

### Run the doctor
```bash
docker compose -f backend/docker-compose.yml exec backend bin/rails erp:doctor
```
Checks DB reachability, user count, admin password match, roles/permissions seeded, Redis, Sidekiq, Shopify env.

### Recovery runbook
```bash
# 1. My DB got wiped (I ran with -v by mistake)
docker compose -f backend/docker-compose.yml up -d          # re-creates schema + re-seeds on boot

# 2. I changed ADMIN_PASSWORD in .env and now can't log in
docker compose -f backend/docker-compose.yml exec backend bin/rails db:seed
# Seeds use find_or_initialize_by, so this just resyncs the password hash.

# 3. I think my backend is pointing at the wrong database
docker compose -f backend/docker-compose.yml exec backend bin/rails erp:doctor
# Line "Database reachable (erp_development)" confirms the DB name.
```

> Note: `bin/rails db:test:prepare` touches only `erp_test`. It cannot delete dev users.

