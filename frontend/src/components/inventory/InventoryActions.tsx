import { useEffect, useState } from "react";
import api from "../../api/client";
import {
  inventorySyncApi,
  showroomSalesApi,
  stockTransfersApi,
  type Warehouse,
} from "../../api/inventory";

interface VariantOption {
  id: string;
  title: string;
  sku: string;
  product_title: string;
}

export function ShopifyBackfillButton({ onDone }: { onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const run = async () => {
    if (
      !confirm(
        "Pull all inventory levels from Shopify? This may take a minute.",
      )
    )
      return;
    setBusy(true);
    setMsg(null);
    try {
      const stats = await inventorySyncApi.shopifyBackfill();
      setMsg(
        `OK: ${stats.applied}/${stats.levels} levels at ${stats.locations} locations`,
      );
      onDone();
    } catch (e) {
      setMsg("Failed: " + ((e as Error).message || "unknown"));
    } finally {
      setBusy(false);
      setTimeout(() => setMsg(null), 6000);
    }
  };
  return (
    <div className="relative">
      <button
        onClick={run}
        disabled={busy}
        className="inline-flex items-center gap-1 bg-slate-700 disabled:bg-slate-400 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-slate-800"
      >
        {busy ? "Syncing…" : "Sync Shopify"}
      </button>
      {msg && (
        <div className="absolute top-full right-0 mt-1 text-xs bg-white border border-slate-200 shadow rounded px-2 py-1 whitespace-nowrap z-10">
          {msg}
        </div>
      )}
    </div>
  );
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
      api
        .get<{ data: VariantOption[] }>("/variants", {
          params: { per_page: 500 },
        })
        .then((r) => setVariants(r.data.data))
        .catch(() => undefined);
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
      {open && (
        <div className="fixed inset-0 z-50 bg-black/30 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-5">
            <h3 className="text-lg font-semibold mb-3">Transfer stock</h3>
            <form onSubmit={submit} className="space-y-3">
              <label className="block text-sm">
                <span className="block text-slate-600 mb-1">Variant</span>
                <select
                  required
                  value={variantId}
                  onChange={(e) => setVariantId(e.target.value)}
                  className="w-full border border-slate-300 rounded px-3 py-2"
                >
                  <option value="">Select variant…</option>
                  {variants.map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.product_title} — {v.title} ({v.sku})
                    </option>
                  ))}
                </select>
              </label>
              <div className="grid grid-cols-2 gap-3">
                <label className="text-sm">
                  <span className="block text-slate-600 mb-1">From</span>
                  <select
                    required
                    value={from}
                    onChange={(e) => setFrom(e.target.value)}
                    className="w-full border border-slate-300 rounded px-3 py-2"
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
                    className="w-full border border-slate-300 rounded px-3 py-2"
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
                  className="w-full border border-slate-300 rounded px-3 py-2"
                />
              </label>
              {error && (
                <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
                  {error}
                </div>
              )}
              <div className="flex justify-end gap-2 pt-1">
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="text-sm px-3 py-1.5 rounded border border-slate-300"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="text-sm bg-amber-600 hover:bg-amber-700 text-white font-medium px-4 py-1.5 rounded"
                >
                  Transfer
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
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
  const [currency, setCurrency] = useState("USD");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<ReportLine[]>([
    { variant_id: "", quantity: "", unit_price: "" },
  ]);
  const [variants, setVariants] = useState<VariantOption[]>([]);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const showrooms = warehouses.filter((w) => w.kind === "consignment");

  useEffect(() => {
    if (open && variants.length === 0) {
      api
        .get<{ data: VariantOption[] }>("/variants", {
          params: { per_page: 500 },
        })
        .then((r) => setVariants(r.data.data))
        .catch(() => undefined);
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
      await showroomSalesApi.create({
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
      {open && (
        <div className="fixed inset-0 z-50 bg-black/30 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-3xl p-5 max-h-[90vh] overflow-y-auto">
            <h3 className="text-lg font-semibold mb-1">
              Post showroom sales report
            </h3>
            <p className="text-xs text-slate-500 mb-4">
              Records sales sold by a consignment showroom. Posts a sales
              journal entry, COGS, and deducts inventory at the showroom.
            </p>
            <form onSubmit={submit} className="space-y-3">
              <div className="grid grid-cols-3 gap-3">
                <label className="text-sm">
                  <span className="block text-slate-600 mb-1">Showroom *</span>
                  <select
                    required
                    value={warehouseId}
                    onChange={(e) => setWarehouseId(e.target.value)}
                    className="w-full border border-slate-300 rounded px-3 py-2"
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
                    className="w-full border border-slate-300 rounded px-3 py-2"
                  />
                </label>
                <label className="text-sm">
                  <span className="block text-slate-600 mb-1">Currency</span>
                  <input
                    value={currency}
                    onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                    maxLength={3}
                    className="w-full border border-slate-300 rounded px-3 py-2 uppercase"
                  />
                </label>
              </div>

              {showrooms.length === 0 && (
                <div className="bg-amber-50 text-amber-800 text-sm p-2 rounded">
                  No consignment warehouses yet. Create one with kind
                  "consignment" first (Inventory → New stock item picks the
                  warehouse, but to add a new showroom go to /inventory and use
                  the warehouse selector after API creation).
                </div>
              )}

              <div className="border border-slate-200 rounded">
                <table className="w-full text-sm">
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
                                {v.product_title} — {v.title} ({v.sku})
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
                <button
                  type="button"
                  onClick={() =>
                    setLines((arr) => [
                      ...arr,
                      { variant_id: "", quantity: "", unit_price: "" },
                    ])
                  }
                  className="w-full text-xs text-indigo-600 hover:bg-indigo-50 py-1.5 border-t border-slate-200"
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
                  className="w-full border border-slate-300 rounded px-3 py-2"
                />
              </label>

              {error && (
                <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
                  {error}
                </div>
              )}

              <div className="flex justify-end gap-2 pt-1">
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="text-sm px-3 py-1.5 rounded border border-slate-300"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="text-sm bg-emerald-600 hover:bg-emerald-700 disabled:bg-slate-400 text-white font-medium px-4 py-1.5 rounded"
                >
                  {submitting ? "Posting…" : "Post report"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
