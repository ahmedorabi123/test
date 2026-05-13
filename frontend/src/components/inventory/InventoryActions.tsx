import { useEffect, useState } from "react";
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

export function TransferStockButton({
  warehouses,
  onDone,
}: {
  warehouses: Warehouse[];
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [variantId, setVariantId] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [qty, setQty] = useState("");
  const [variants, setVariants] = useState<VariantOption[]>([]);
  const [error, setError] = useState("");

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
    try {
      await stockTransfersApi.create({
        variant_id: variantId,
        from_warehouse_id: from,
        to_warehouse_id: to,
        quantity: Number(qty),
      });
      setOpen(false);
      setVariantId("");
      setFrom("");
      setTo("");
      setQty("");
      onDone();
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data
          ?.error || (e as Error).message;
      setError(msg);
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
        onClose={() => setOpen(false)}
        size="md"
        title="Transfer stock"
      >
        <form onSubmit={submit} className="space-y-3">
          <label className="block text-sm">
            <span className="block text-slate-600 mb-1">Variant</span>
            <select
              required
              value={variantId}
              onChange={(e) => setVariantId(e.target.value)}
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
            >
              <option value="">Select variant…</option>
              {variants.map((v) => (
                <option key={v.id} value={v.id}>
                  {variantLabel(v)}
                </option>
              ))}
            </select>
          </label>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">From</span>
              <select
                required
                value={from}
                onChange={(e) => setFrom(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="">—</option>
                {warehouses.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name} ({w.code})
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-slate-600 mb-1">To</span>
              <select
                required
                value={to}
                onChange={(e) => setTo(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              >
                <option value="">—</option>
                {warehouses
                  .filter((w) => w.id !== from)
                  .map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.name} ({w.code})
                      {w.kind === "consignment" ? " · showroom" : ""}
                    </option>
                  ))}
              </select>
            </label>
          </div>
          <label className="block text-sm">
            <span className="block text-slate-600 mb-1">Quantity</span>
            <input
              type="number"
              min={1}
              required
              value={qty}
              onChange={(e) => setQty(e.target.value)}
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
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
              className="min-h-11 rounded bg-amber-600 px-4 text-sm font-medium text-white hover:bg-amber-700"
            >
              Transfer
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

export function ShowroomReportButton({
  warehouses,
  onDone,
}: {
  warehouses: Warehouse[];
  onDone: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [warehouseId, setWarehouseId] = useState("");
  const [period, setPeriod] = useState(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
  });
  const [currency, setCurrency] = useState("EGP");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<ReportLine[]>([
    { variant_id: "", quantity: "", unit_price: "" },
  ]);
  const [variants, setVariants] = useState<VariantOption[]>([]);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [lastOrder, setLastOrder] = useState<{
    id: string;
    order_number: string;
  } | null>(null);

  const showrooms = warehouses.filter((w) => w.kind === "consignment");
  const noShowrooms = showrooms.length === 0;

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
    const valid = lines.filter(
      (l) =>
        l.variant_id && Number(l.quantity) > 0 && Number(l.unit_price) >= 0,
    );
    if (valid.length === 0) {
      setError("Add at least one line with quantity and price");
      return;
    }
    setSubmitting(true);
    try {
      const created = await showroomSalesApi.create({
        warehouse_id: warehouseId,
        period,
        currency,
        notes: notes || undefined,
        line_items: valid.map((l) => ({
          variant_id: l.variant_id,
          quantity: Number(l.quantity),
          unit_price: l.unit_price,
        })),
      });
      setLastOrder({ id: created.id, order_number: created.order_number });
      setOpen(false);
      setLines([{ variant_id: "", quantity: "", unit_price: "" }]);
      setNotes("");
      onDone();
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data
          ?.error || (e as Error).message;
      setError(msg);
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
      {lastOrder && (
        <div className="fixed bottom-4 right-4 z-50 max-w-sm rounded-lg border border-emerald-200 bg-emerald-50 p-3 shadow-lg">
          <div className="flex items-start gap-3">
            <div className="text-sm text-emerald-900">
              <div className="font-medium">Showroom report posted</div>
              <div className="text-xs">Order {lastOrder.order_number}</div>
            </div>
            <Link
              to={`/orders/${lastOrder.id}`}
              className="text-xs font-medium text-emerald-700 underline hover:text-emerald-900"
              onClick={() => setLastOrder(null)}
            >
              View order
            </Link>
            <button
              type="button"
              onClick={() => setLastOrder(null)}
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
        onClose={() => setOpen(false)}
        size="xl"
        title="Post showroom sales report"
        description="Records sales sold by a consignment showroom. Posts a sales journal entry, COGS, and deducts inventory at the showroom."
      >
        <form onSubmit={submit} className="space-y-3">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
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
              <span className="block text-slate-600 mb-1">Period *</span>
              <input
                type="month"
                required
                value={period}
                onChange={(e) => setPeriod(e.target.value)}
                className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
              />
            </label>
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
                          min={0}
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
