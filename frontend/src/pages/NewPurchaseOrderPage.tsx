import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { productsApi, type Product, type Variant } from "../api/products";
import { warehousesApi, type Warehouse } from "../api/inventory";
import { suppliersApi, type Supplier } from "../api/suppliers";
import { purchaseOrdersApi } from "../api/purchaseOrders";

interface Line {
  variant_id: string;
  title: string;
  sku: string;
  quantity_ordered: number;
  unit_cost: number;
  cost_source: string;
}

function defaultUnitCost(variant: Variant) {
  const configuredCost = Number(variant.cost ?? 0);
  if (configuredCost > 0) {
    return { value: configuredCost, source: "from variant cost" };
  }

  const lastPurchaseCost = Number(variant.last_purchase_cost ?? 0);
  if (lastPurchaseCost > 0) {
    return { value: lastPurchaseCost, source: "from last PO" };
  }

  return { value: 0, source: "manual" };
}

export default function NewPurchaseOrderPage() {
  const navigate = useNavigate();
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [variants, setVariants] = useState<
    Array<Variant & { product_title: string }>
  >([]);
  const [supplierId, setSupplierId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [expectedAt, setExpectedAt] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([]);
  const [selectedVariant, setSelectedVariant] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const [s, w, p] = await Promise.all([
        suppliersApi.list({ per_page: 100 }),
        warehousesApi.list(),
        productsApi.list({ per_page: 100, status: "active" }),
      ]);
      setSuppliers(s.data);
      setWarehouses(w);
      const all: Array<Variant & { product_title: string }> = [];
      for (const prod of p.data as Product[]) {
        const full = await productsApi.get(prod.id);
        (full.variants || []).forEach((v: Variant) =>
          all.push({ ...v, product_title: prod.title }),
        );
      }
      setVariants(all);
    })().catch((e) => setError((e as Error).message));
  }, []);

  const total = useMemo(
    () => lines.reduce((s, l) => s + l.quantity_ordered * l.unit_cost, 0),
    [lines],
  );

  const addLine = () => {
    const v = variants.find((x) => x.id === selectedVariant);
    if (!v) return;
    const cost = defaultUnitCost(v);
    setLines((ls) => [
      ...ls,
      {
        variant_id: v.id,
        title: `${v.product_title} – ${v.title}`,
        sku: v.sku || "",
        quantity_ordered: 1,
        unit_cost: cost.value,
        cost_source: cost.source,
      },
    ]);
    setSelectedVariant("");
  };

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      if (!supplierId) throw new Error("Select a supplier");
      if (lines.length === 0) throw new Error("Add at least one line item");
      const po = await purchaseOrdersApi.create({
        supplier_id: supplierId,
        warehouse_id: warehouseId || undefined,
        expected_at: expectedAt || undefined,
        notes: notes || undefined,
        line_items: lines.map((l) => ({
          variant_id: l.variant_id,
          sku: l.sku,
          title: l.title,
          quantity_ordered: Number(l.quantity_ordered),
          unit_cost: Number(l.unit_cost),
        })),
      });
      navigate(`/purchases/${po.id}`);
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(err.response?.data?.error?.detail || err.message || "Failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="max-w-3xl p-4 sm:p-6">
      <h1 className="text-2xl font-semibold mb-4">New Purchase Order</h1>
      {error && (
        <div className="bg-red-100 text-red-700 p-2 mb-3 rounded">{error}</div>
      )}

      <div className="space-y-3 bg-white p-4 rounded shadow">
        <div>
          <label className="text-sm font-medium block mb-1">Supplier</label>
          <select
            value={supplierId}
            onChange={(e) => setSupplierId(e.target.value)}
            className="min-h-11 w-full rounded border px-2 py-1"
          >
            <option value="">— select supplier —</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="text-sm font-medium block mb-1">
            Warehouse (receive into)
          </label>
          <select
            value={warehouseId}
            onChange={(e) => setWarehouseId(e.target.value)}
            className="min-h-11 w-full rounded border px-2 py-1"
          >
            <option value="">— none —</option>
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label className="text-sm font-medium block mb-1">
              Expected at
            </label>
            <input
              type="date"
              value={expectedAt}
              onChange={(e) => setExpectedAt(e.target.value)}
              className="min-h-11 w-full rounded border px-2 py-1"
            />
          </div>
        </div>

        <div>
          <label className="text-sm font-medium block mb-1">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full border rounded px-2 py-1"
            rows={2}
          />
        </div>
      </div>

      <div className="mt-6 bg-white p-4 rounded shadow">
        <h2 className="font-semibold mb-3">Line items</h2>

        <div className="flex gap-2 mb-3">
          <select
            value={selectedVariant}
            onChange={(e) => setSelectedVariant(e.target.value)}
            className="min-h-11 flex-1 rounded border px-2 py-1"
          >
            <option value="">— add variant —</option>
            {variants.map((v) => (
              <option key={v.id} value={v.id}>
                {v.product_title} – {v.title} ({v.sku})
              </option>
            ))}
          </select>
          <button
            onClick={addLine}
            disabled={!selectedVariant}
            className="min-h-11 rounded bg-indigo-600 px-3 text-white disabled:opacity-50"
          >
            Add
          </button>
        </div>

        <div className="overflow-x-auto">
        <table className="min-w-[680px] text-sm">
          <thead className="bg-gray-50 text-left">
            <tr>
              <th className="px-2 py-1">Item</th>
              <th className="px-2 py-1 text-right">Qty</th>
              <th className="px-2 py-1 text-right">Unit cost</th>
              <th className="px-2 py-1 text-right">Subtotal</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={i} className="border-t">
                <td className="px-2 py-1">{l.title}</td>
                <td className="px-2 py-1 text-right">
                  <input
                    type="number"
                    min={1}
                    value={l.quantity_ordered}
                    onChange={(e) =>
                      setLines((ls) =>
                        ls.map((x, j) =>
                          j === i
                            ? { ...x, quantity_ordered: Number(e.target.value) }
                            : x,
                        ),
                      )
                    }
                    className="w-20 border rounded px-1 py-0.5 text-right"
                  />
                </td>
                <td className="px-2 py-1 text-right">
                  <input
                    type="number"
                    min={0}
                    step="0.01"
                    value={l.unit_cost}
                    onChange={(e) =>
                      setLines((ls) =>
                        ls.map((x, j) =>
                          j === i
                            ? {
                                ...x,
                                unit_cost: Number(e.target.value),
                                cost_source: "manual",
                              }
                            : x,
                        ),
                      )
                    }
                    className="w-24 border rounded px-1 py-0.5 text-right"
                  />
                  <div className="mt-1 text-[11px] text-slate-500">
                    {l.cost_source}
                  </div>
                </td>
                <td className="px-2 py-1 text-right">
                  {(l.quantity_ordered * l.unit_cost).toFixed(2)}
                </td>
                <td className="px-2 py-1 text-right">
                  <button
                    onClick={() =>
                      setLines((ls) => ls.filter((_, j) => j !== i))
                    }
                    className="text-red-600 hover:underline text-xs"
                  >
                    remove
                  </button>
                </td>
              </tr>
            ))}
            {lines.length === 0 && (
              <tr>
                <td colSpan={5} className="px-2 py-4 text-center text-gray-500">
                  No line items
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr className="border-t font-semibold bg-gray-50">
              <td colSpan={3} className="px-2 py-2 text-right">
                Total
              </td>
              <td className="px-2 py-2 text-right">{total.toFixed(2)}</td>
              <td />
            </tr>
          </tfoot>
        </table>
        </div>
      </div>

      <div className="mt-4 flex gap-2">
        <button
          onClick={submit}
          disabled={busy}
          className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded disabled:opacity-50"
        >
          {busy ? "Creating…" : "Create purchase order"}
        </button>
      </div>
    </div>
  );
}
