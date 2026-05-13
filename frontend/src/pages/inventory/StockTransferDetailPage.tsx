import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { stockTransfersApi, type StockTransfer } from "../../api/inventory";

export default function StockTransferDetailPage() {
  const { id = "" } = useParams<{ id: string }>();
  const [transfer, setTransfer] = useState<StockTransfer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    stockTransfersApi
      .get(id)
      .then(setTransfer)
      .catch((e: Error) => setError(e.message))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) return <div className="p-4">Loading…</div>;
  if (error)
    return (
      <div className="p-4 bg-red-50 text-red-700 rounded">{error}</div>
    );
  if (!transfer) return <div className="p-4">Not found</div>;

  return (
    <div className="p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold">{transfer.reference}</h1>
          <div className="text-sm text-slate-600">
            {transfer.from_warehouse_name || transfer.from_warehouse_code} →{" "}
            {transfer.to_warehouse_name || transfer.to_warehouse_code} ·{" "}
            {transfer.reason} · {transfer.status}
            {transfer.posted_at && (
              <> · {new Date(transfer.posted_at).toLocaleString()}</>
            )}
          </div>
        </div>
        <Link
          to="/inventory/transfers"
          className="text-sm text-indigo-600 underline hover:text-indigo-800"
        >
          ← All transfers
        </Link>
      </div>

      {transfer.note && (
        <div className="rounded bg-slate-50 p-3 text-sm text-slate-700">
          {transfer.note}
        </div>
      )}

      <section>
        <h2 className="font-medium mb-2">Lines ({transfer.line_count})</h2>
        <div className="rounded border border-slate-200 overflow-x-auto">
          <table className="min-w-[480px] text-sm">
            <thead className="bg-slate-50 text-xs uppercase text-slate-600">
              <tr>
                <th className="px-3 py-2 text-left">SKU</th>
                <th className="px-3 py-2 text-left">Variant</th>
                <th className="px-3 py-2 text-right">Quantity</th>
              </tr>
            </thead>
            <tbody>
              {(transfer.lines || []).map((l) => (
                <tr key={l.id || l.variant_id} className="border-t border-slate-100">
                  <td className="px-3 py-2">{l.sku || "—"}</td>
                  <td className="px-3 py-2">
                    {l.product_title} — {l.variant_title}
                  </td>
                  <td className="px-3 py-2 text-right">{l.quantity}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="font-medium mb-2">Movements</h2>
        <div className="rounded border border-slate-200 overflow-x-auto">
          <table className="min-w-[640px] text-sm">
            <thead className="bg-slate-50 text-xs uppercase text-slate-600">
              <tr>
                <th className="px-3 py-2 text-left">Stock item</th>
                <th className="px-3 py-2 text-right">Delta</th>
                <th className="px-3 py-2 text-right">Before</th>
                <th className="px-3 py-2 text-right">After</th>
                <th className="px-3 py-2 text-left">Reason</th>
                <th className="px-3 py-2 text-left">When</th>
              </tr>
            </thead>
            <tbody>
              {(transfer.movements || []).map((m) => (
                <tr key={m.id} className="border-t border-slate-100">
                  <td className="px-3 py-2 text-xs font-mono">
                    {m.stock_item_id}
                  </td>
                  <td
                    className={
                      "px-3 py-2 text-right " +
                      (m.delta < 0 ? "text-red-600" : "text-emerald-700")
                    }
                  >
                    {m.delta > 0 ? `+${m.delta}` : m.delta}
                  </td>
                  <td className="px-3 py-2 text-right">{m.snapshot_before}</td>
                  <td className="px-3 py-2 text-right">{m.snapshot_after}</td>
                  <td className="px-3 py-2">{m.reason}</td>
                  <td className="px-3 py-2 text-slate-500">
                    {new Date(m.created_at).toLocaleString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
