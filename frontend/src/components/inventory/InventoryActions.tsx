import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import api from "../../api/client";
import {
  showroomSalesApi,
  stockTransfersApi,
  type Warehouse,
} from "../../api/inventory";
import { Modal } from "../ui/Modal";

interface VariantOption {
  id: string;
  title: string;
  sku: string | null;
  product_title: string | null;
  shopify_variant_id?: number | null;
  read_only_origin?: boolean;
  product_source?: "manual" | "shopify";
  product_shopify_product_id?: number | null;
  product_read_only_origin?: boolean;
}

interface VariantsResponse {
  data: VariantOption[];
  meta?: {
    page: number;
    per_page: number;
    total: number;
  };
}

function variantLabel(variant: VariantOption) {
  const product = variant.product_title || "Product";
  const sku = variant.sku ? ` (${variant.sku})` : "";
  return `${product} - ${variant.title}${sku}`;
}

function isWarehouseMutable(warehouse: Warehouse) {
  return Boolean(
    warehouse.active &&
      !warehouse.read_only_origin &&
      !warehouse.shopify_location_id,
  );
}

async function fetchAllVariants() {
  const variants: VariantOption[] = [];
  let page = 1;
  let total = Infinity;

  do {
    const response = await api.get<VariantsResponse>("/variants", {
      params: { page, per_page: 100 },
    });
    variants.push(...response.data.data);
    total = response.data.meta?.total ?? variants.length;
    if (response.data.data.length === 0) break;
    page += 1;
  } while (variants.length < total);

  return variants;
}

interface TransferLine {
  variant_id: string;
  quantity: string;
}

export function TransferStockButton({
  warehouses,
  onDone,
}: {
  warehouses: Warehouse[];
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [reason, setReason] = useState("transfer");
  const [note, setNote] = useState("");
  const [lines, setLines] = useState<TransferLine[]>([
    { variant_id: "", quantity: "" },
  ]);
  const [variants, setVariants] = useState<VariantOption[]>([]);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Stable handler so the Modal's focus-management effect doesn't re-fire on
  // every parent render (which would steal focus from inputs as the user types).
  const handleClose = useCallback(() => setOpen(false), []);

  // Shopify-origin warehouses are read-only — exclude them from the source
  // and destination lists.
  const eligible = warehouses.filter(isWarehouseMutable);
  const noEligible = eligible.length < 2;

  useEffect(() => {
    if (open && variants.length === 0) {
      fetchAllVariants()
        .then(setVariants)
        .catch(() => setVariants([]));
    }
  }, [open, variants.length]);

  const reset = () => {
    setFrom("");
    setTo("");
    setReason("transfer");
    setNote("");
    setLines([{ variant_id: "", quantity: "" }]);
    setError("");
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    const valid = lines.filter((l) => l.variant_id && Number(l.quantity) > 0);
    if (valid.length === 0) {
      setError("Add at least one line with a variant and a positive quantity");
      return;
    }
    const ids = valid.map((l) => l.variant_id);
    if (new Set(ids).size !== ids.length) {
      setError("Each variant can appear at most once");
      return;
    }
    setSubmitting(true);
    try {
      await stockTransfersApi.createBatch({
        stock_transfer: {
          from_warehouse_id: from,
          to_warehouse_id: to,
          reason,
          note: note || undefined,
        },
        lines: valid.map((l) => ({
          variant_id: l.variant_id,
          quantity: Number(l.quantity),
        })),
      });
      setOpen(false);
      reset();
      onDone();
    } catch (e) {
      const resp = (
        e as {
          response?: { data?: { error?: { detail?: string; type?: string } } };
        }
      )?.response?.data?.error;
      setError(resp?.detail || (e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1 bg-amber-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-amber-700"
      >
        Transfer
      </button>
      <Modal
        open={open}
        onClose={handleClose}
        size="xl"
        title="Transfer stock"
        description="Move one or more variants from a source warehouse to a destination. Shopify-managed warehouses are read-only and excluded."
      >
        <form onSubmit={submit} className="space-y-3">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">From *</span>
              <select
                required
                value={from}
                onChange={(e) => setFrom(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="">—</option>
                {eligible.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name} ({w.code})
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">To *</span>
              <select
                required
                value={to}
                onChange={(e) => setTo(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="">—</option>
                {eligible
                  .filter((w) => w.id !== from)
                  .map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.name} ({w.code})
                      {w.kind === "consignment" ? " · showroom" : ""}
                    </option>
                  ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Reason</span>
              <select
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="transfer">Transfer</option>
                <option value="restock">Restock</option>
                <option value="showroom_prep">Showroom prep</option>
                <option value="return">Return</option>
                <option value="rebalance">Rebalance</option>
                <option value="other">Other</option>
              </select>
            </label>
          </div>

          {noEligible && (
            <div className="bg-amber-50 text-amber-800 text-sm p-2 rounded">
              At least two non-Shopify warehouses are required to transfer
              stock.
            </div>
          )}

          <div className="rounded border border-slate-200">
            <div className="overflow-x-auto">
              <table className="min-w-[480px] text-sm">
                <thead className="bg-slate-50 text-xs text-slate-600 uppercase">
                  <tr>
                    <th className="px-2 py-2 text-left">Variant</th>
                    <th className="px-2 py-2 text-right w-28">Quantity</th>
                    <th className="w-8"></th>
                  </tr>
                </thead>
                <tbody>
                  {lines.map((l, idx) => (
                    <tr key={idx} className="border-t border-slate-100">
                      <td className="px-2 py-1">
                        <select
                          value={l.variant_id}
                          onChange={(e) =>
                            setLines((arr) =>
                              arr.map((x, i) =>
                                i === idx
                                  ? { ...x, variant_id: e.target.value }
                                  : x,
                              ),
                            )
                          }
                          className="w-full border border-slate-200 rounded px-2 py-1"
                        >
                          <option value="">—</option>
                          {variants.map((v) => (
                            <option key={v.id} value={v.id}>
                              {variantLabel(v)}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-2 py-1">
                        <input
                          type="number"
                          min={1}
                          step={1}
                          value={l.quantity}
                          onChange={(e) =>
                            setLines((arr) =>
                              arr.map((x, i) =>
                                i === idx
                                  ? { ...x, quantity: e.target.value }
                                  : x,
                              ),
                            )
                          }
                          className="w-full border border-slate-200 rounded px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-2 py-1 text-center">
                        <button
                          type="button"
                          onClick={() =>
                            setLines((arr) =>
                              arr.length === 1
                                ? arr
                                : arr.filter((_, i) => i !== idx),
                            )
                          }
                          className="text-red-500 hover:text-red-700 text-sm"
                          aria-label="Remove line"
                          title="Remove"
                        >
                          ×
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <button
              type="button"
              onClick={() =>
                setLines((arr) => [...arr, { variant_id: "", quantity: "" }])
              }
              className="min-h-10 w-full border-t border-slate-200 py-1.5 text-xs text-indigo-600 hover:bg-indigo-50"
            >
              + Add line
            </button>
          </div>

          <label className="block text-sm">
            <span className="block text-slate-600 mb-1">Note</span>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
              className="w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>

          {error && (
            <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
              {error}
            </div>
          )}

          <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="min-h-11 rounded border border-slate-300 px-3 text-sm"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting || noEligible}
              className="min-h-11 rounded bg-amber-600 px-4 text-sm font-medium text-white hover:bg-amber-700 disabled:bg-slate-400"
            >
              {submitting ? "Transferring…" : "Transfer"}
            </button>
          </div>
        </form>
      </Modal>
    </>
  );
}

interface ReportLine {
  variant_id: string;
  quantity: string;
  unit_price: string;
}

type PeriodMode = "day" | "week" | "ten_days" | "month" | "custom";

function isoDate(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function isoMonth(date = new Date()) {
  return date.toISOString().slice(0, 7);
}

function addDays(value: string, days: number) {
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function periodKey(
  mode: PeriodMode,
  start: string,
  end: string,
  month: string,
) {
  if (mode === "month") return month;
  if (mode === "day") return start;
  if (mode === "week") return `${start}..${addDays(start, 6)}`;
  if (mode === "ten_days") return `${start}..${addDays(start, 9)}`;
  return `${start}..${end}`;
}

function reportDateFor(mode: PeriodMode, start: string, month: string) {
  return mode === "month" ? `${month}-01` : start;
}

export function ShowroomReportButton({
  warehouses,
  onDone,
}: {
  warehouses: Warehouse[];
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [warehouseId, setWarehouseId] = useState("");
  const [periodMode, setPeriodMode] = useState<PeriodMode>("month");
  const [periodStart, setPeriodStart] = useState(() => isoDate());
  const [periodEnd, setPeriodEnd] = useState(() => isoDate());
  const [periodMonth, setPeriodMonth] = useState(() => isoMonth());
  const [currency, setCurrency] = useState("EGP");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<ReportLine[]>([
    { variant_id: "", quantity: "", unit_price: "" },
  ]);
  const [variants, setVariants] = useState<VariantOption[]>([]);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [lastResult, setLastResult] = useState<{
    orderId?: string;
    orderNumber?: string;
    salesTotal: string;
    reversalTotal: string;
    reversalId?: string;
  } | null>(null);

  // Stable handler so the Modal's focus-management effect doesn't re-fire on
  // every parent render (which would steal focus from inputs as the user types).
  const handleClose = useCallback(() => setOpen(false), []);

  const showrooms = warehouses.filter(
    (w) => w.kind === "consignment" && isWarehouseMutable(w),
  );
  const noShowrooms = showrooms.length === 0;
  const period = periodKey(
    periodMode,
    periodStart,
    periodEnd,
    periodMonth,
  );
  const reportDate = reportDateFor(periodMode, periodStart, periodMonth);

  useEffect(() => {
    if (open && variants.length === 0) {
      fetchAllVariants()
        .then(setVariants)
        .catch(() => setVariants([]));
    }
  }, [open, variants.length]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    // Quantities may be negative — those rows post an accounting-only sales
    // reversal with no inventory movement. Zero is rejected.
    const valid = lines.filter(
      (l) =>
        l.variant_id &&
        Number(l.quantity) !== 0 &&
        l.unit_price !== "" &&
        Number(l.unit_price) >= 0,
    );
    if (valid.length === 0) {
      setError("Add at least one line with a non-zero quantity and a price");
      return;
    }
    if (periodMode === "custom" && periodEnd < periodStart) {
      setError("End date must be on or after the start date");
      return;
    }
    setSubmitting(true);
    try {
      const created = await showroomSalesApi.create({
        warehouse_id: warehouseId,
        period,
        report_date: reportDate,
        currency,
        notes: notes || undefined,
        line_items: valid.map((l) => ({
          variant_id: l.variant_id,
          quantity: Number(l.quantity),
          unit_price: l.unit_price,
        })),
      });
      setLastResult({
        orderId: created.order?.id || created.id,
        orderNumber: created.order?.order_number || created.order_number,
        salesTotal: created.sales_total,
        reversalTotal: created.reversal_total,
        reversalId: created.reversal?.id,
      });
      setOpen(false);
      setLines([{ variant_id: "", quantity: "", unit_price: "" }]);
      setNotes("");
      onDone();
    } catch (e) {
      const resp = (
        e as { response?: { data?: { error?: { detail?: string } } } }
      )?.response?.data?.error;
      setError(resp?.detail || (e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1 bg-emerald-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-emerald-700"
      >
        Showroom report
      </button>
      {lastResult && (
        <div className="fixed bottom-4 right-4 z-50 max-w-sm rounded-lg border border-emerald-200 bg-emerald-50 p-3 shadow-lg">
          <div className="flex items-start gap-3">
            <div className="text-sm text-emerald-900">
              <div className="font-medium">Showroom report posted</div>
              {lastResult.orderNumber && (
                <div className="text-xs">Order {lastResult.orderNumber}</div>
              )}
              <div className="text-xs" data-testid="showroom-sales-total">
                Sales: {lastResult.salesTotal}
              </div>
              {Number(lastResult.reversalTotal) > 0 && (
                <div className="text-xs" data-testid="showroom-reversal-total">
                  Reversal: {lastResult.reversalTotal}
                </div>
              )}
            </div>
            {lastResult.orderId && (
              <Link
                to={`/orders/${lastResult.orderId}`}
                className="text-xs font-medium text-emerald-700 underline hover:text-emerald-900"
                onClick={() => setLastResult(null)}
              >
                View order
              </Link>
            )}
            <button
              type="button"
              onClick={() => setLastResult(null)}
              className="text-emerald-700 hover:text-emerald-900"
              aria-label="Dismiss"
            >
              ×
            </button>
          </div>
        </div>
      )}
      <Modal
        open={open}
        onClose={handleClose}
        size="xl"
        title="Post showroom sales report"
        description="Records sales sold by a consignment showroom. Posts a sales journal entry, COGS, and deducts inventory at the showroom."
      >
        <form onSubmit={submit} className="space-y-3">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-5">
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Showroom *</span>
              <select
                required
                value={warehouseId}
                onChange={(e) => setWarehouseId(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="">Select showroom…</option>
                {showrooms.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name} ({w.code})
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Period type</span>
              <select
                value={periodMode}
                onChange={(e) => setPeriodMode(e.target.value as PeriodMode)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="day">Day</option>
                <option value="week">Week</option>
                <option value="ten_days">10 days</option>
                <option value="month">Month</option>
                <option value="custom">Custom</option>
              </select>
            </label>
            {periodMode === "month" ? (
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">Month *</span>
                <input
                  type="month"
                  required
                  value={periodMonth}
                  onChange={(e) => setPeriodMonth(e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
            ) : (
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">Start date *</span>
                <input
                  type="date"
                  required
                  value={periodStart}
                  onChange={(e) => setPeriodStart(e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
            )}
            {periodMode === "custom" ? (
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">End date *</span>
                <input
                  type="date"
                  required
                  value={periodEnd}
                  onChange={(e) => setPeriodEnd(e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
            ) : (
              <div className="hidden md:block" aria-hidden="true" />
            )}
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">Currency</span>
              <input
                value={currency}
                onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                maxLength={3}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2 uppercase"
              />
            </label>
          </div>

          {showrooms.length === 0 && (
            <div className="bg-amber-50 text-amber-800 text-sm p-2 rounded">
              Create a consignment warehouse to post a showroom report. Go to
              Warehouses and add a warehouse with kind "consignment" first.
            </div>
          )}

          <div className="rounded border border-slate-200">
            <div className="overflow-x-auto">
              <table className="min-w-[620px] text-sm">
                <thead className="bg-slate-50 text-xs text-slate-600 uppercase">
                  <tr>
                    <th className="px-2 py-2 text-left">Variant</th>
                    <th className="px-2 py-2 text-right w-24">Qty</th>
                    <th className="px-2 py-2 text-right w-28">Unit price</th>
                    <th className="w-8"></th>
                  </tr>
                </thead>
                <tbody>
                  {lines.map((l, idx) => (
                    <tr key={idx} className="border-t border-slate-100">
                      <td className="px-2 py-1">
                        <select
                          value={l.variant_id}
                          onChange={(e) =>
                            setLines((arr) =>
                              arr.map((x, i) =>
                                i === idx
                                  ? { ...x, variant_id: e.target.value }
                                  : x,
                              ),
                            )
                          }
                          className="w-full border border-slate-200 rounded px-2 py-1"
                        >
                          <option value="">—</option>
                          {variants.map((v) => (
                            <option key={v.id} value={v.id}>
                              {variantLabel(v)}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-2 py-1">
                        <input
                          type="number"
                          step={1}
                          value={l.quantity}
                          aria-label="Quantity"
                          placeholder="e.g. 2 or -1"
                          onChange={(e) =>
                            setLines((arr) =>
                              arr.map((x, i) =>
                                i === idx
                                  ? { ...x, quantity: e.target.value }
                                  : x,
                              ),
                            )
                          }
                          className="w-full border border-slate-200 rounded px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-2 py-1">
                        <input
                          type="number"
                          step="0.01"
                          min={0}
                          value={l.unit_price}
                          onChange={(e) =>
                            setLines((arr) =>
                              arr.map((x, i) =>
                                i === idx
                                  ? { ...x, unit_price: e.target.value }
                                  : x,
                              ),
                            )
                          }
                          className="w-full border border-slate-200 rounded px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-2 py-1 text-center">
                        <button
                          type="button"
                          onClick={() =>
                            setLines((arr) => arr.filter((_, i) => i !== idx))
                          }
                          className="text-red-500 hover:text-red-700 text-sm"
                          title="Remove"
                        >
                          ×
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <button
              type="button"
              onClick={() =>
                setLines((arr) => [
                  ...arr,
                  { variant_id: "", quantity: "", unit_price: "" },
                ])
              }
              className="min-h-10 w-full border-t border-slate-200 py-1.5 text-xs text-indigo-600 hover:bg-indigo-50"
            >
              + Add line
            </button>
          </div>

          <label className="block text-sm">
            <span className="block text-slate-600 mb-1">Notes</span>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              className="w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>

          {error && (
            <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
              {error}
            </div>
          )}

          <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="min-h-11 rounded border border-slate-300 px-3 text-sm"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting || noShowrooms}
              className="min-h-11 rounded bg-emerald-600 px-4 text-sm font-medium text-white hover:bg-emerald-700 disabled:bg-slate-400"
            >
              {submitting ? "Posting…" : "Post report"}
            </button>
          </div>
        </form>
      </Modal>
    </>
  );
}
