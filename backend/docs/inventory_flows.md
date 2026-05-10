# Inventory Flows

This document describes the four core inventory flows in shopify_erp_2 and the
expected UI/UX behaviour for each. It complements `lifecycle.md`
(order/payment/fulfillment lifecycle).

## 1. Stock provisioning

When a `Variant` is created, `Inventory::ProvisionStockItemsJob` ensures one
`StockItem` row exists per active warehouse for that variant.

- Implementation: `Inventory::StockProvisioner` performs a bulk
  `StockItem.insert_all([...], unique_by: %i[variant_id warehouse_id])`.
- The `unique_by:` clause guarantees idempotency at the database level — re-runs
  of the job for the same variant are safe (no duplicate rows, no exceptions).
- The job is enqueued from `Catalog::Shopify::ProductUpserter` (after each
  variant upsert) and from `Variant#after_create_commit`.

### Edge cases

| Scenario                                      | Result                          |
|-----------------------------------------------|---------------------------------|
| Variant deleted before job runs               | No-op (job logs and returns).   |
| Warehouse added later                         | Backfilled by re-running the job.|
| Warehouse `archived_at` is set                | Skipped (only active warehouses).|

## 2. Manual transfer between warehouses

Move quantity from one warehouse to another atomically.

```
TransferStockButton          POST /api/v1/stock_transfers
    (frontend)        ────►          (controller)        ────►  Inventory::TransferStock
                                                                  (service)
```

- The service runs inside a single `ActiveRecord::Base.transaction`.
- `available = quantity_on_hand - quantity_reserved`. Reservations are
  respected — you cannot transfer stock that is reserved for an open order.
- Insufficient stock raises `Inventory::TransferStock::InsufficientStock` with
  message `only N available` (surfaced in the UI as a toast).
- Two `StockMovement` rows are written:
  - source warehouse: `delta = -quantity`, `reason = "transfer"`
  - destination warehouse: `delta = +quantity`, `reason = "transfer"`

### Frontend UX

- `TransferStockButton` (`frontend/src/pages/Inventory/TransferStockButton.tsx`)
  opens a modal with: source warehouse, destination warehouse, variant, quantity.
- Submit is disabled while the request is in-flight.
- On success a toast confirms `Transferred N units`.

## 3. Showroom (Estebdal) sales report

The "Showroom Report" tool lets an operator close out a consignment warehouse
period (e.g. weekly) by uploading a CSV / form of variant×quantity sales. Each
report posts:

1. A sale `JournalEntry` (revenue + receivable).
2. A COGS `JournalEntry`.
3. One `StockMovement` per line (`reason = "showroom_sale"`).
4. A backing `Order` for traceability and refund support.

### Idempotency

Each report carries a deterministic period tag of the form
`[showroom:<warehouse_code>:<period>]` (and CSV imports additionally embed
`[showroom_csv:<warehouse_code>:<order_num>:<sha1[12]>]` in notes). Re-submitting
the same report short-circuits — no duplicate journal entries or movements.

### UI guidance — Phase 2 contract

Implemented in `frontend/src/pages/Inventory/InventoryActions.tsx`:

- The **Showroom Report** action is disabled when the workspace has no
  consignment warehouses; the empty-state hint reads
  *"Add a consignment warehouse to enable this action"*.
- On success the toast surfaces a deep link:
  ```tsx
  toast.success(<>Report posted. <Link to={`/orders/${id}`}>View order</Link></>)
  ```
- Validation errors from the backend (e.g. `period already closed`) surface
  inline next to the affected field.

## 4. Reservations and the order lifecycle

Stock reservations are the bridge between sales and inventory. See
`lifecycle.md` for the full state machine; the inventory-side rules are:

| Order transition          | Inventory effect                                             |
|---------------------------|--------------------------------------------------------------|
| `pending → processing`    | None (reservations were created at order creation).          |
| `processing → fulfilled`  | `Inventory::ConsumeReservation` per fulfillment line item: decrements `quantity_on_hand` and writes a `fulfilled` `StockMovement`. |
| `* → cancelled`           | `Inventory::ReleaseOrderReservations`: marks all `active` reservations as `released`, restoring availability. |
| Refund with `restock=true`| `Inventory::WriteMovement(reason: "refund_restock", delta: +qty)` per refund line. |

All of these are wrapped in `safe { … }` blocks inside
`Sales::OrderStateMachine` so a side-effect failure logs but does not roll back
the status transition.

---

### Tests

| Flow                           | Spec                                                     |
|--------------------------------|----------------------------------------------------------|
| Provisioning (no-op + dispatch)| `spec/jobs/shopify_domain_jobs_spec.rb`                  |
| Manual transfer happy path     | `spec/domains/inventory/transfer_stock_spec.rb`          |
| Showroom report                | `spec/integration/manual_showroom_inventory_lifecycle_spec.rb` |
| Lifecycle (cross-module)       | `spec/integration/order_lifecycle_matrix_spec.rb`        |
