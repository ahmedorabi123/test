import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  stockTransfersApi,
  warehousesApi,
  type StockTransfer,
  type Warehouse,
} from "../../api/inventory";

export default function StockTransfersPage() {
  const [transfers, setTransfers] = useState<StockTransfer[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [warehouseFilter, setWarehouseFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  useEffect(() => {
    warehousesApi.list().then(setWarehouses).catch(() => undefined);
  }, []);

  useEffect(() => {
    setLoading(true);
    stockTransfersApi
      .list({
        from_warehouse_id: warehouseFilter || undefined,
        status: statusFilter || undefined,
      })
      .then((r) => setTransfers(r.data))
      .catch((e: Error) => setError(e.message))
      .finally(() => setLoading(false));
  }, [warehouseFilter, statusFilter]);

  return (
    <div className="p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-xl font-semibold">Stock transfers</h1>
        <Link
          to="/inventory"
          className="text-sm text-indigo-600 underline hover:text-indigo-800"
        >
          Back to inventory
        </Link>
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm">
          <span className="block text-slate-600 mb-1">Source warehouse</span>
          <select
            value={warehouseFilter}
            onChange={(e) => setWarehouseFilter(e.target.value)}
            className="min-h-10 rounded border border-slate-300 px-3 py-1"
          >
            <option value="">All</option>
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name} ({w.code})
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          <span className="block text-slate-600 mb-1">Status</span>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="min-h-10 rounded border border-slate-300 px-3 py-1"
          >
            <option value="">All</option>
            <option value="posted">Posted</option>
            <option value="draft">Draft</option>
            <option value="cancelled">Cancelled</option>
          </select>
        </label>
      </div>

      {error && (
        <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
          {error}
        </div>
      )}

      <div className="rounded border border-slate-200 overflow-x-auto">
        <table className="min-w-[720px] text-sm">
          <thead className="bg-slate-50 text-xs uppercase text-slate-600">
            <tr>
              <th className="px-3 py-2 text-left">Reference</th>
              <th className="px-3 py-2 text-left">From</th>
              <th className="px-3 py-2 text-left">To</th>
              <th className="px-3 py-2 text-right">Lines</th>
              <th className="px-3 py-2 text-right">Units</th>
              <th className="px-3 py-2 text-left">Reason</th>
              <th className="px-3 py-2 text-left">Status</th>
              <th className="px-3 py-2 text-left">Posted</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={8} className="px-3 py-4 text-center text-slate-500">
                  Loading…
                </td>
              </tr>
            ) : transfers.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-3 py-4 text-center text-slate-500">
                  No stock transfers yet.
                </td>
              </tr>
            ) : (
              transfers.map((t) => (
                <tr key={t.id} className="border-t border-slate-100">
                  <td className="px-3 py-2">
                    <Link
                      to={`/inventory/transfers/${t.id}`}
                      className="text-indigo-600 underline hover:text-indigo-800"
                    >
                      {t.reference}
                    </Link>
                  </td>
                  <td className="px-3 py-2">
                    {t.from_warehouse_name || t.from_warehouse_code}
                  </td>
                  <td className="px-3 py-2">
                    {t.to_warehouse_name || t.to_warehouse_code}
                  </td>
                  <td className="px-3 py-2 text-right">{t.line_count}</td>
                  <td className="px-3 py-2 text-right">{t.total_quantity}</td>
                  <td className="px-3 py-2">{t.reason}</td>
                  <td className="px-3 py-2">{t.status}</td>
                  <td className="px-3 py-2 text-slate-500">
                    {t.posted_at ? new Date(t.posted_at).toLocaleString() : "—"}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
