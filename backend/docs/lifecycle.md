# System Lifecycles

This document traces the lifecycle of every major entity in the ERP, end-to-end:
where it is born (Shopify webhook, manual UI, CSV import), every job/service it
visits, the side effects it triggers in other modules, and the terminal states
it can reach.

> Conventions
>
> - **Sync flow**: in-process Ruby calls (controller → service → model).
> - **Async flow**: Sidekiq job dispatched via `perform_later` (or via the
>   transactional outbox).
> - **Event**: a row written to `domain_events` and then projected/handled.

---

## 1. Order — from Shopify

```
Shopify  ──HTTPS POST (HMAC-signed)──▶  /webhooks/shopify  (controller)
                                              │
                                              ▼
                                   Webhooks::ShopifyController
                                   - verifies HMAC
                                   - persists WebhookEvent (raw payload)
                                   - enqueues ProcessShopifyWebhookJob
                                              │
                                              ▼
                            Sidekiq: ProcessShopifyWebhookJob
                                   - re-loads payload from WebhookEvent
                                   - delegates by topic
                                              │
                                              ▼
                            Shopify::EventNormalizer
                                   - shape-checks the payload
                                   - returns a normalized Hash
                                              │
                                              ▼
                            HandleShopifyOrderJob
                                              │
                                              ▼
                            Sales::Shopify::OrderUpserter
                                   - find_or_initialize by shopify_order_id
                                   - upserts order, line_items, addresses
                                   - sets source: "shopify"
                                   - on financial_status == "paid":
                                        Accounting::PostSaleJournalHandler
                                   - on refund payload:
                                        Accounting::RefundReversalHandler
                                              │
                                              ▼
                            DomainEvent (`order.upserted`)
                                              │
                                              ▼
                       Indexing::OrderIndexer (OpenSearch projection)
```

Terminal states (`status × financial_status`):

| status     | financial_status     |
| ---------- | -------------------- |
| pending    | pending / authorized |
| processing | paid                 |
| fulfilled  | paid                 |
| cancelled  | refunded / voided    |

---

## 2. Order — manual creation (Sales UI)

```
POST /api/v1/orders   →  OrdersController#create
                              │
                              ▼
                   Sales::ManualOrderCreator
                   - resolves customer (by id or by email)
                   - builds line items from variant_id (price snapshot)
                   - computes subtotal/tax/discount/shipping/total
                   - if mark_paid: PostSaleJournalHandler
                              │
                              ▼
                       DomainEvent (`order.created`)
                              │
                              ▼
                   Indexing::OrderIndexer
```

After creation, status changes go through:

```
POST /api/v1/orders/:id/transition  { to: "processing" | "fulfilled" | "paid" | "cancelled" | … }
                              │
                              ▼
                   Sales::OrderStateMachine
                   - validates against LEGAL_STATUS / LEGAL_FINANCIAL
                   - on "fulfilled":  Inventory::WriteMovement (delta=-qty,
                                       reason="fulfilled") for each line item
                   - on "paid":        PostSaleJournalHandler (idempotent)
                   - on "refunded" or
                     cancel-after-paid: RefundReversalHandler
                   - writes AuditLog row
```

---

## 3. Order — CSV / Shopify-export import (showroom mode)

```
POST /api/v1/orders/import          (preview)
POST /api/v1/orders/import/commit   (commit)
                              │
                              ▼
                   Imports::ShowroomSalesImporter
                   - parses CSV/XLSX showroom rows
                   - groups by Order #
                   - delegates each order to Sales::ManualOrderCreator
                   - source: "showroom"
                   - paid rows reserve stock and post sale journals
                   - returns { created, updated, errors }
```

No webhook is triggered; no journal is posted unless rows include `paid`.

---

## 4. Product

### 4.1 From Shopify

```
webhook (products/create | products/update)
   → ProcessShopifyWebhookJob
   → Shopify::EventNormalizer
   → HandleShopifyProductJob
   → Catalog::Shopify::ProductUpserter
        - upserts Product (incl. tags, seo_*, published_*, gift_card)
        - upserts Variants (option1/2/3, weight, inventory_policy,
                            cost_per_item, hs_code, country_of_origin, …)
        - upserts ProductOption + ProductOptionValue
        - upserts ProductImage (by shopify_image_id)
   → Indexing::ProductIndexer
```

### 4.2 Manual

```
POST /api/v1/products
   → ProductsController#create
   → permits nested product_options_attributes / product_images_attributes
   → Indexing::ProductIndexer
```

### 4.3 CSV import

Imports::ProductsImporter accepts the official Shopify product CSV columns
(Tags, SEO Title/Description, Option1 Name/Value, Variant Inventory Tracker,
Variant Inventory Policy, Variant Grams, Variant Cost, Image Src, …).

---

## 5. Customer

```
Shopify webhook            → HandleShopifyCustomerJob → Crm::Shopify::CustomerUpserter
Manual POST /customers     → CustomersController#create
CSV import                 → Imports::CustomersImporter
```

All paths emit a `customer.upserted` DomainEvent which is consumed by
`Indexing::CustomerIndexer`.

---

## 6. Refund

Two entry points:

1. **Shopify webhook** (`refunds/create`) → `Sales::Shopify::RefundUpserter`.
     It upserts the Refund and RefundLineItems, restocks inventory when Shopify
     marks a line as `return`, releases cancelled reservations for `cancel`,
     updates order financial state, and posts accounting:
     - full refund: `Accounting::RefundReversalHandler`
     - partial refund: `Accounting::PartialRefundJournalHandler`
2. **Manual ERP refund** → `Sales::ManualRefundCreator`. It validates amount,
     optional restock warehouse, and positive line items when restocking; then it
     creates the Refund, writes restock movements, posts the partial refund
     journal, updates order totals/status, and recomputes customer stats.

`Accounting::PartialRefundJournalHandler` is idempotent by
`refund-partial-<refund_id>` and locks the order and refund while checking and
posting the journal entry.

---

## 7. Fulfillment

A fulfillment row is created either:

- **Manual ERP flow** through `Shipping::CreateManualFulfillment`, which creates
     a Fulfillment and FulfillmentLineItems, consumes reservations, posts COGS if
     cost data exists, records a shipment event, and transitions the order when
     legal.
- **Shopify webhook** (`fulfillments/create|update`) through
     `Shipping::Shopify::FulfillmentUpserter`, which upserts the Fulfillment,
     syncs line items, consumes inventory the first time a fulfillment becomes
     successful, posts COGS, and records shipment events.

Reservation consumption runs through `Inventory::ConsumeReservation`, which
locks the FulfillmentLineItem, OrderLineItem, active reservation, and StockItem
before re-checking idempotency and writing the `fulfilled` StockMovement.

---

## 8. Purchase Order

Pure ERP entity, no Shopify equivalent.

```
POST /api/v1/purchase_orders
   → PurchaseOrdersController#create
   → Purchases::PurchaseOrderCreator
        - validates supplier, lines
        - status: draft
   → state transitions: draft → submitted → received → closed
        - on "received": Inventory::WriteMovement (delta=+qty, reason="purchase")
        - on "closed":   Accounting::PostPurchaseJournalHandler
```

---

## 9. Cross-module integration diagram

```
┌──────────────┐      ┌──────────────┐      ┌─────────────────┐
│   Shopify    │─────▶│  Webhooks    │─────▶│  Sidekiq Queue  │
└──────────────┘      └──────────────┘      └─────────────────┘
                                                     │
                ┌───────────────┬────────────────────┼────────────────┬──────────────┐
                ▼               ▼                    ▼                ▼              ▼
        ProductUpserter  CustomerUpserter   OrderUpserter   FulfillmentJob   InventoryJob
                │               │                    │                │              │
                │               │                    ▼                ▼              ▼
                │               │            Accounting          Inventory     StockSyncSvc
                │               │           (PostSale /         (WriteMovement)
                │               │            RefundReversal)
                ▼               ▼                    │
           ┌────────────────────────────────┐        │
           │       DomainEvent log          │◀───────┘
           └────────────────────────────────┘
                       │
                       ▼
                ┌──────────────┐
                │  OpenSearch  │
                │   indexers   │
                └──────────────┘
```

---

## 10. State machines summary

**Order.status**: `pending → processing → fulfilled`, any `→ cancelled`.

**Order.financial_status**:
`pending → authorized → paid → (partially_paid | refunded)`,
also `pending → voided`, `authorized → voided`.

Enforced by `Sales::OrderStateMachine` (authoritative) — direct `update` on
the model is also allowed but bypasses side effects.

---

## 11. Idempotency And Locking

| Flow | Idempotency key / guard | Locking |
| ---- | ----------------------- | ------- |
| Shopify webhook receipt | `webhook_events(source, external_id)` | DB unique index |
| Sale journal | `sale-journal-<order_id>` | JournalEntry unique index |
| Partial refund journal | `refund-partial-<refund_id>` | Locks order + refund before post |
| Full refund reversal | `refund-reversal-<order_id>` | JournalEntry unique index |
| COGS journal | `cogs-<fulfillment_id>` | JournalEntry unique index |
| Fulfillment inventory consume | existing `StockMovement(reference, reason="fulfilled")` | Locks fulfillment line, order line, reservation, stock item |
| Manual refund create | explicit idempotency_key or recent content hash | DB unique index where key present |
| Stock transfer | paired StockMovement rows under a StockItem transaction | Locks source and destination stock items |
