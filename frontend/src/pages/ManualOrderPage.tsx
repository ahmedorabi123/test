import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import api from "../api/client";
import { customersApi, type Customer } from "../api/customers";
import { ordersApi } from "../api/orders";
import { warehousesApi, type Warehouse } from "../api/inventory";

type Line = {
  key: string;
  variant_id: string;
  title: string;
  sku: string | null;
  price: string;
  quantity: number;
};

interface VariantHit {
  id: string;
  sku: string | null;
  title: string | null;
  price: string;
  product_id: string;
  product_title: string;
  stock_items?: Array<{
    warehouse_id: string;
    available: number;
    quantity_on_hand: number;
  }>;
}

export default function ManualOrderPage() {
  const navigate = useNavigate();
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const [source, setSource] = useState<"manual" | "showroom">("showroom");
  const [customerId, setCustomerId] = useState<string>("");
  const [customerEmail, setCustomerEmail] = useState("");
  const [customerName, setCustomerName] = useState("");
  const [notes, setNotes] = useState("");
  const [totalShipping, setTotalShipping] = useState("0.00");
  const [markPaid, setMarkPaid] = useState(true);
  const [warehouseId, setWarehouseId] = useState("");
  const [lines, setLines] = useState<Line[]>([]);

  // Variant typeahead state — replaces the prior eager N+1 product fetch.
  const [variantQuery, setVariantQuery] = useState("");
  const [variantHits, setVariantHits] = useState<VariantHit[]>([]);
  const [variantSearching, setVariantSearching] = useState(false);
  const [variantById, setVariantById] = useState<Record<string, VariantHit>>(
    {},
  );

  useEffect(() => {
    (async () => {
      try {
        const { data } = await customersApi.list({ per_page: 100 });
        setCustomers(data);
      } catch {
        // optional
      }
      try {
        const rows = await warehousesApi.list();
        const activeRows = rows.filter((warehouse) => warehouse.active);
        setWarehouses(activeRows);
        setWarehouseId((current) => current || activeRows[0]?.id || "");
      } catch {
        // optional
      }
    })();
  }, []);

  // Debounced variant search via /variants?search=&include=stock_items_summary
  useEffect(() => {
    const q = variantQuery.trim();
    if (q.length < 2) {
      setVariantHits([]);
      return;
    }
    let cancelled = false;
    setVariantSearching(true);
    const t = setTimeout(async () => {
      try {
        const res = await api.get<{ data: VariantHit[] }>("/variants", {
          params: {
            search: q,
            per_page: 25,
            include: "stock_items_summary",
            warehouse_id: warehouseId || undefined,
          },
        });
        if (!cancelled) setVariantHits(res.data.data);
      } catch {
        if (!cancelled) setVariantHits([]);
      } finally {
        if (!cancelled) setVariantSearching(false);
      }
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [variantQuery, warehouseId]);

  const addVariant = (v: VariantHit) => {
    setVariantById((prev) => ({ ...prev, [v.id]: v }));
    const titleParts = [v.product_title, v.title].filter(Boolean);
    setLines((prev) => [
      ...prev,
      {
        key: `${Date.now()}-${Math.random()}`,
        variant_id: v.id,
        title: titleParts.join(" · "),
        sku: v.sku,
        price: v.price,
        quantity: 1,
      },
    ]);
    setVariantQuery("");
    setVariantHits([]);
  };

  const updateLine = (key: string, patch: Partial<Line>) =>
    setLines((prev) =>
      prev.map((l) => (l.key === key ? { ...l, ...patch } : l)),
    );
  const removeLine = (key: string) =>
    setLines((prev) => prev.filter((l) => l.key !== key));

  const subtotal = lines.reduce(
    (acc, l) => acc + Number(l.price) * Number(l.quantity || 0),
    0,
  );
  const shipping = Number(totalShipping || 0);
  const total = subtotal + shipping;

  const canSubmit = lines.length > 0 && !submitting;

  const availabilityFor = (variantId: string) => {
    const v = variantById[variantId];
    if (!v?.stock_items?.length) return null;
    if (warehouseId) {
      const item = v.stock_items.find((i) => i.warehouse_id === warehouseId);
      return item?.available ?? null;
    }
    return v.stock_items.reduce((acc, i) => acc + (i.available ?? 0), 0);
  };


  const submit = async () => {
    if (!canSubmit) return;
    setSubmitting(true);
    setError(null);
    try {
      const order = await ordersApi.create({
        source,
        customer_id: customerId || undefined,
        customer_email: customerEmail || undefined,
        customer_name: customerName || undefined,
        notes: notes || undefined,
        total_shipping: shipping.toFixed(2),
        mark_paid: markPaid,
        warehouse_id: warehouseId || undefined,
        line_items: lines.map((l) => ({
          variant_id: l.variant_id,
          sku: l.sku ?? undefined,
          title: l.title,
          quantity: l.quantity,
          price: l.price,
        })),
      });
      navigate(`/orders?created=${order.order_number}`);
    } catch (e) {
      type ApiErr = {
        response?: {
          data?: {
            error?: { detail?: string; shortages?: Array<{ sku?: string }> };
          };
        };
      };
      const err = e as ApiErr;
      const shortages = err?.response?.data?.error?.shortages;
      const shortageText = shortages?.length
        ? ` (${shortages.map((row) => row.sku || "variant").join(", ")})`
        : "";
      setError(
        err?.response?.data?.error?.detail ||
          `${(e as Error).message || "Failed to create order"}${shortageText}`,
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="mx-auto max-w-5xl p-4 sm:p-6">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-slate-900">
          New manual order
        </h1>
        <p className="text-sm text-slate-500 mt-1">
          Create a showroom / phone-in order. Inventory and accounting are
          updated immediately when marked paid.
        </p>
      </div>

      {error && (
        <div className="mb-4 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm">
          <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1">
            Source
          </label>
          <select
            value={source}
            onChange={(e) => setSource(e.target.value as "manual" | "showroom")}
            className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="showroom">Showroom</option>
            <option value="manual">Manual</option>
          </select>
        </div>
        <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm">
          <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1">
            Warehouse
          </label>
          <select
            value={warehouseId}
            onChange={(e) => setWarehouseId(e.target.value)}
            className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="">Auto-select</option>
            {warehouses.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </select>
        </div>
        <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm md:col-span-1">
          <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1">
            Customer
          </label>
          <select
            value={customerId}
            onChange={(e) => {
              const id = e.target.value;
              setCustomerId(id);
              const c = customers.find((x) => x.id === id);
              if (c) {
                setCustomerEmail(c.email || "");
                setCustomerName(c.display_name || "");
              }
            }}
            className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500 mb-2"
          >
            <option value="">— Walk-in / anonymous —</option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.display_name} {c.email ? `<${c.email}>` : ""}
              </option>
            ))}
          </select>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <input
              type="text"
              placeholder="Customer name"
              value={customerName}
              onChange={(e) => setCustomerName(e.target.value)}
              className="border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <input
              type="email"
              placeholder="Customer email"
              value={customerEmail}
              onChange={(e) => setCustomerEmail(e.target.value)}
              className="border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
        </div>
      </div>

      <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm mb-6">
        <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="text-sm font-medium text-slate-700">Line items</div>
          <div className="relative w-full sm:w-80">
            <input
              type="text"
              value={variantQuery}
              onChange={(e) => setVariantQuery(e.target.value)}
              placeholder="Search variant by SKU, name, product…"
              className="w-full border border-slate-300 rounded-md px-3 py-1.5 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
            />
            {variantQuery.trim().length >= 2 && (
              <div className="absolute z-10 mt-1 w-full max-h-72 overflow-auto rounded-md border border-slate-200 bg-white shadow-lg">
                {variantSearching && (
                  <div className="px-3 py-2 text-xs text-slate-500">
                    Searching…
                  </div>
                )}
                {!variantSearching && variantHits.length === 0 && (
                  <div className="px-3 py-2 text-xs text-slate-500">
                    No matches
                  </div>
                )}
                {variantHits.map((v) => (
                  <button
                    key={v.id}
                    type="button"
                    onClick={() => addVariant(v)}
                    className="block w-full text-left px-3 py-2 hover:bg-indigo-50 text-sm"
                  >
                    <div className="font-medium text-slate-800">
                      {v.product_title}
                      {v.title ? ` · ${v.title}` : ""}
                    </div>
                    <div className="text-xs text-slate-500 flex justify-between">
                      <span className="font-mono">{v.sku || "—"}</span>
                      <span>{v.price}</span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {lines.length === 0 && (
          <div className="text-center py-10 text-sm text-slate-400">
            No line items yet. Pick a variant above to add one.
          </div>
        )}

        {lines.map((l) => (
          <div
            key={l.key}
            className="grid grid-cols-1 gap-2 border-b border-slate-100 py-3 last:border-b-0 sm:grid-cols-12 sm:items-center sm:py-2"
          >
            <div className="text-sm text-slate-900 sm:col-span-5 sm:truncate">
              {l.title}
              {warehouseId && (
                <div className="text-xs text-slate-500">
                  Available: {availabilityFor(l.variant_id) ?? "not stocked"}
                </div>
              )}
            </div>
            <div className="font-mono text-xs text-slate-500 sm:col-span-2">
              {l.sku || "—"}
            </div>
            <input
              type="number"
              min={1}
              value={l.quantity}
              onChange={(e) =>
                updateLine(l.key, {
                  quantity: Math.max(1, Number(e.target.value)),
                })
              }
              className="min-h-10 rounded-md border border-slate-300 px-2 py-1 text-sm outline-none focus:ring-2 focus:ring-indigo-500 sm:col-span-1"
            />
            <input
              type="text"
              value={l.price}
              onChange={(e) => updateLine(l.key, { price: e.target.value })}
              className="min-h-10 rounded-md border border-slate-300 px-2 py-1 text-sm outline-none focus:ring-2 focus:ring-indigo-500 sm:col-span-2"
            />
            <div className="text-sm text-slate-700 sm:col-span-1 sm:text-right">
              {(Number(l.price) * Number(l.quantity)).toFixed(2)}
            </div>
            <button
              onClick={() => removeLine(l.key)}
              className="min-h-10 text-left text-sm text-rose-500 hover:text-rose-700 sm:col-span-1 sm:text-center"
            >
              Remove
            </button>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm">
          <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={3}
            className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-indigo-500"
          />
        </div>
        <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-sm space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-slate-600">Subtotal</span>
            <span className="font-medium text-slate-900">
              {subtotal.toFixed(2)}
            </span>
          </div>
          <div className="flex items-center justify-between text-sm gap-2">
            <span className="text-slate-600">Shipping</span>
            <input
              type="text"
              value={totalShipping}
              onChange={(e) => setTotalShipping(e.target.value)}
              className="w-24 border border-slate-300 rounded-md px-2 py-1 text-sm text-right outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
          <div className="flex items-center justify-between text-base pt-2 border-t border-slate-200">
            <span className="text-slate-700 font-medium">Total</span>
            <span className="font-semibold text-slate-900">
              {total.toFixed(2)}
            </span>
          </div>
          <label className="flex items-center gap-2 text-sm text-slate-700 pt-2">
            <input
              type="checkbox"
              checked={markPaid}
              onChange={(e) => setMarkPaid(e.target.checked)}
              className="rounded border-slate-300"
            />
            Mark paid & post sale journal now
          </label>
        </div>
      </div>

      <div className="flex justify-end gap-3">
        <button
          onClick={() => navigate("/orders")}
          className="px-4 py-2 text-sm border border-slate-300 text-slate-700 rounded-lg hover:bg-slate-50"
        >
          Cancel
        </button>
        <button
          onClick={submit}
          disabled={!canSubmit}
          className="px-4 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50"
        >
          {submitting ? "Creating…" : "Create order"}
        </button>
      </div>
    </div>
  );
}
