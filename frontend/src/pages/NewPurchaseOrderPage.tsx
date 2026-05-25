import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { warehousesApi, type Warehouse } from "../api/inventory";
import { suppliersApi, type Supplier } from "../api/suppliers";
import { purchaseOrdersApi } from "../api/purchaseOrders";
import { variantsApi, type VariantLookup } from "../api/variants";

interface Line {
  variant_id: string;
  title: string;
  sku: string;
  quantity_ordered: number;
}

export default function NewPurchaseOrderPage() {
  const navigate = useNavigate();
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [variantOptions, setVariantOptions] = useState<VariantLookup[]>([]);
  const [variantSearch, setVariantSearch] = useState("");
  const [selectedVariant, setSelectedVariant] = useState<VariantLookup | null>(
    null,
  );
  const [supplierId, setSupplierId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [expectedAt, setExpectedAt] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const variantBoxRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (!variantBoxRef.current) return;
      if (!variantBoxRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  useEffect(() => {
    (async () => {
      const [s, w, variantRows] = await Promise.all([
        suppliersApi.list({ per_page: 100, kind: "factory" }),
        warehousesApi.list(),
        variantsApi.list({ per_page: 25 }),
      ]);
      setSuppliers(s.data);
      setWarehouses(w);
      setVariantOptions(variantRows.data);
    })().catch((e) => setError((e as Error).message));
  }, []);

  useEffect(() => {
    const q = variantSearch.trim();
    const handle = setTimeout(
      async () => {
        const res = await variantsApi.list({
          search: q || undefined,
          per_page: q ? 25 : 15,
        });
        setVariantOptions(res.data);
      },
      q ? 250 : 0,
    );
    return () => clearTimeout(handle);
  }, [variantSearch]);

  const totalQty = useMemo(
    () => lines.reduce((s, l) => s + Number(l.quantity_ordered || 0), 0),
    [lines],
  );

  const addLine = () => {
    const v = selectedVariant;
    if (!v) return;
    setLines((ls) => [
      ...ls,
      {
        variant_id: v.id,
        title: `${v.product_title ?? "Product"} – ${v.title}`,
        sku: v.sku || "",
        quantity_ordered: 1,
      },
    ]);
    setSelectedVariant(null);
    setVariantSearch("");
    setDropdownOpen(false);
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
          <div className="relative flex-1" ref={variantBoxRef}>
            <input
              value={
                selectedVariant
                  ? `${selectedVariant.product_title ?? "Product"} – ${selectedVariant.title}${selectedVariant.sku ? ` (${selectedVariant.sku})` : ""}`
                  : variantSearch
              }
              onChange={(e) => {
                setSelectedVariant(null);
                setVariantSearch(e.target.value);
                setDropdownOpen(true);
              }}
              onFocus={() => setDropdownOpen(true)}
              onClick={() => setDropdownOpen(true)}
              onKeyDown={(e) => { if (e.key === "Escape") setDropdownOpen(false); }}
              placeholder="Search SKU, variant, or product title…"
              className="min-h-11 w-full rounded border px-2 py-1"
            />
            {dropdownOpen && !selectedVariant && variantOptions.length > 0 && (
              <div className="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded border border-slate-200 bg-white shadow-lg">
                {variantOptions.map((v) => (
                  <button
                    type="button"
                    key={v.id}
                    onClick={() => { setSelectedVariant(v); setDropdownOpen(false); }}
                    className="block w-full px-3 py-2 text-left text-sm hover:bg-indigo-50"
                  >
                    <span className="font-medium text-slate-900">
                      {v.product_title} – {v.title}
                    </span>
                    <span className="ml-2 font-mono text-xs text-slate-500">
                      {v.sku || "no SKU"}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
          <button
            onClick={addLine}
            disabled={!selectedVariant}
            className="min-h-11 rounded bg-indigo-600 px-3 text-white disabled:opacity-50"
          >
            Add
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="min-w-[480px] text-sm">
            <thead className="bg-gray-50 text-left">
              <tr>
                <th className="px-2 py-1">Item</th>
                <th className="px-2 py-1 text-right">Qty</th>
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
                              ? {
                                  ...x,
                                  quantity_ordered: Number(e.target.value),
                                }
                              : x,
                          ),
                        )
                      }
                      className="w-20 border rounded px-1 py-0.5 text-right"
                    />
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
                  <td
                    colSpan={3}
                    className="px-2 py-4 text-center text-gray-500"
                  >
                    No line items
                  </td>
                </tr>
              )}
            </tbody>
            <tfoot>
              <tr className="border-t font-semibold bg-gray-50">
                <td className="px-2 py-2 text-right">Total qty</td>
                <td className="px-2 py-2 text-right">{totalQty}</td>
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
