# UI Testing Guide

End-to-end manual testing playbook for the ERP. Use this after a fresh
`bin/erp-setup` (which seeds RBAC users and a small product catalog).

## 1. Environment

```bash
docker compose -f backend/docker-compose.yml up -d
docker compose -f frontend/docker-compose.yml up -d
```

- Backend: http://localhost:3010
- Frontend: http://localhost:5174
- Postgres: localhost:54321 (db `shopify_erp_dev`)

## 2. Seeded users

| Email                | Role       | Password     | Can…                                 |
| -------------------- | ---------- | ------------ | ------------------------------------ |
| admin@erp.local      | admin      | changeme123! | everything                           |
| ops@erp.local        | ops        | changeme123! | manage products / orders / inventory |
| accountant@erp.local | accountant | changeme123! | read all + post journal entries      |
| viewer@erp.local     | viewer     | changeme123! | read-only across all modules         |

### RBAC matrix (high-level)

| Action                             | admin | ops | accountant | viewer |
| ---------------------------------- | :---: | :-: | :--------: | :----: |
| List products / orders / customers |  ✅   | ✅  |     ✅     |   ✅   |
| Create / edit product              |  ✅   | ✅  |     ❌     |   ❌   |
| Import / export product            |  ✅   | ✅  |     ❌     |   ❌   |
| Create order (manual)              |  ✅   | ✅  |     ❌     |   ❌   |
| Transition order status            |  ✅   | ✅  |     ❌     |   ❌   |
| Cancel / refund order              |  ✅   | ✅  |     ❌     |   ❌   |
| Post journal entry                 |  ✅   | ❌  |     ✅     |   ❌   |
| Manage users / roles               |  ✅   | ❌  |     ❌     |   ❌   |

## 3. Per-page checklists

### Login

- [ ] Wrong password → red toast, no token persisted.
- [ ] Successful login redirects to `/dashboard`.
- [ ] Refreshing the page keeps you signed in (JWT in localStorage).

### Products list

- [ ] Pagination shows correct counts.
- [ ] Search filters by title / SKU / vendor.
- [ ] Clicking a column header cycles **▲ asc → ▼ desc → no sort**.
- [ ] Export → CSV / JSON / XLSX downloads with correct columns
      (incl. Tags, SEO Title, SEO Description, Published At).
- [ ] Import → upload Shopify CSV → preview shows row counts → commit.
- [ ] Bulk actions: select N rows, archive/unarchive.

### Product form (Shopify-style)

- [ ] Title, body, vendor, type, status, tags, SEO panel.
- [ ] Add / reorder images.
- [ ] Add up to 3 options (Color/Size/Material) — variant grid auto-generates.
- [ ] Each variant: price, compare-at, cost, sku, barcode, qty, weight, taxable,
      requires shipping, country of origin, HS code, fulfillment service.

### Customers

- [ ] Same import/export/sort cycle as products.

### Orders list

- [ ] Filters: status, financial_status, source, date range.
- [ ] Status badges color-coded.
- [ ] Sort cycle on every column header.

### Order detail — full lifecycle clickthrough

1. Create a manual order with 2 line items, `mark_paid: false`.
2. On the detail page you should see buttons: **Start processing**,
   **Mark as fulfilled**, **Cancel order** (status), **Mark as authorized**,
   **Mark as paid**, **Void payment** (financial).
3. Click **Mark as paid** → financial_status flips to `paid`, journal entry is
   posted (verify in Accounting → Journal Entries).
4. Click **Mark as fulfilled** → status flips to `fulfilled`, stock movements
   are written (verify in Inventory → Movements, reason=`fulfilled`).
5. Try clicking **Cancel order** → confirm dialog → on success a refund-style
   contra journal is posted.
6. Try an illegal transition (refresh, then click any disabled state) → 422
   with "Cannot move order …".

### Inventory

- [ ] Adjust stock → writes a StockMovement with reason="adjustment".
- [ ] Filter movements by reason / warehouse / variant.
- [ ] StockItem on_hand never goes negative (clamp + warning log).

### Accounting

- [ ] Chart of Accounts read-only listing.
- [ ] Journal entries listing with debits = credits per entry.

## 4. Import / export round-trip

1. Export products as CSV.
2. Edit one row's `Title`.
3. Import the same file → preview shows `updated: 1, created: 0, errors: 0`.
4. Commit → reload products list → title is updated.
5. Repeat for customers and orders.

## 5. Webhook simulation (no Shopify needed)

```bash
export WEBHOOKS_HMAC_BYPASS=true
docker compose -f backend/docker-compose.yml up -d backend

curl -X POST http://localhost:3010/webhooks/shopify \
     -H 'X-Shopify-Topic: orders/create' \
     -H 'X-Shopify-Shop-Domain: dev.myshopify.com' \
     -H 'Content-Type: application/json' \
     --data @spec/fixtures/shopify/order_create.json
```

- Verify `WebhookEvent` row is created.
- Verify Sidekiq processed it: `ProcessShopifyWebhookJob`.
- Verify the order shows up in the UI under Orders, source=`shopify`.

> ⚠️ Never set `WEBHOOKS_HMAC_BYPASS=true` in production.

## 6. Known UI-only manual tests

- [ ] Logout from the user menu clears localStorage.
- [ ] Navigating to a forbidden page (e.g. `/users` as viewer) returns 403.
- [ ] Network failure during list call shows a retry banner.
