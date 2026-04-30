import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { purchaseOrdersApi, type PurchaseOrder } from "../api/purchaseOrders";

const STATUS_STYLES: Record<string, string> = {
  draft: "bg-gray-100 text-gray-700",
  ordered: "bg-blue-100 text-blue-700",
  partial: "bg-amber-100 text-amber-800",
  received: "bg-emerald-100 text-emerald-700",
  cancelled: "bg-red-100 text-red-700",
};

export default function PurchasesPage() {
  const [pos, setPos] = useState<PurchaseOrder[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<string>("");
  const perPage = 25;
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, meta } = await purchaseOrdersApi.list({
        page,
        per_page: perPage,
        status: status || undefined,
      });
      setPos(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load purchase orders");
    } finally {
      setLoading(false);
    }
  }, [page, status]);

  useEffect(() => {
    load();
  }, [load]);

  const pages = Math.max(1, Math.ceil(total / perPage));

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-2xl font-semibold">Purchase Orders</h1>
        <Link
          to="/purchases/new"
          className="bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium px-4 py-2 rounded-md"
        >
          + New PO
        </Link>
      </div>

      <div className="mb-3 flex gap-2">
        <select
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setPage(1);
          }}
          className="border rounded px-2 py-1 text-sm"
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="ordered">Ordered</option>
          <option value="partial">Partial</option>
          <option value="received">Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      {error && (
        <div className="bg-red-100 text-red-700 p-2 mb-3 rounded">{error}</div>
      )}
      {loading && <div className="text-sm text-gray-500">Loading…</div>}

      <div className="bg-white rounded shadow overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-left">
            <tr>
              <th className="px-3 py-2">PO #</th>
              <th className="px-3 py-2">Supplier</th>
              <th className="px-3 py-2">Warehouse</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2 text-right">Total</th>
              <th className="px-3 py-2">Expected</th>
              <th className="px-3 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {pos.map((po) => (
              <tr key={po.id} className="border-t">
                <td className="px-3 py-2 font-mono text-xs">{po.po_number}</td>
                <td className="px-3 py-2">{po.supplier_name}</td>
                <td className="px-3 py-2">{po.warehouse_name || "—"}</td>
                <td className="px-3 py-2">
                  <span
                    className={`inline-block px-2 py-0.5 rounded text-xs ${STATUS_STYLES[po.status]}`}
                  >
                    {po.status}
                  </span>
                </td>
                <td className="px-3 py-2 text-right">
                  {po.currency} {Number(po.total).toFixed(2)}
                </td>
                <td className="px-3 py-2 text-xs text-gray-500">
                  {po.expected_at
                    ? new Date(po.expected_at).toLocaleDateString()
                    : "—"}
                </td>
                <td className="px-3 py-2">
                  <Link
                    to={`/purchases/${po.id}`}
                    className="text-indigo-600 hover:underline text-xs"
                  >
                    Open
                  </Link>
                </td>
              </tr>
            ))}
            {!loading && pos.length === 0 && (
              <tr>
                <td
                  colSpan={7}
                  className="px-3 py-8 text-center text-sm text-gray-500"
                >
                  No purchase orders yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="mt-3 flex items-center justify-between text-sm">
        <span>Total: {total}</span>
        <div className="flex gap-2">
          <button
            disabled={page <= 1}
            onClick={() => setPage((p) => p - 1)}
            className="px-3 py-1 border rounded disabled:opacity-50"
          >
            Prev
          </button>
          <span>
            Page {page} / {pages}
          </span>
          <button
            disabled={page >= pages}
            onClick={() => setPage((p) => p + 1)}
            className="px-3 py-1 border rounded disabled:opacity-50"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
