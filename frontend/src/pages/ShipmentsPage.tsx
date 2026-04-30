import { useCallback, useEffect, useState } from "react";
import { fulfillmentsApi, type Fulfillment } from "../api/fulfillments";

const STATUS_STYLES: Record<string, string> = {
  success: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  open: "bg-blue-50 text-blue-700 ring-blue-600/20",
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  cancelled: "bg-gray-100 text-gray-600 ring-gray-500/20",
  error: "bg-rose-50 text-rose-700 ring-rose-600/20",
  failure: "bg-rose-50 text-rose-700 ring-rose-600/20",
};

export default function ShipmentsPage() {
  const [shipments, setShipments] = useState<Fulfillment[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const perPage = 25;
  const [carrier, setCarrier] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, meta } = await fulfillmentsApi.list({
        page,
        per_page: perPage,
        carrier: carrier || undefined,
      });
      setShipments(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load shipments");
    } finally {
      setLoading(false);
    }
  }, [page, carrier]);

  useEffect(() => {
    load();
  }, [load]);

  const pages = Math.max(1, Math.ceil(total / perPage));

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-end justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Shipments</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total} fulfillment{total === 1 ? "" : "s"} · Bosta + Shopify-driven
          </p>
        </div>
        <select
          value={carrier}
          onChange={(e) => {
            setPage(1);
            setCarrier(e.target.value);
          }}
          className="w-44 border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
        >
          <option value="">All carriers</option>
          <option value="bosta">Bosta</option>
          <option value="dhl">DHL</option>
          <option value="ups">UPS</option>
        </select>
      </div>

      {error && (
        <div className="mb-4 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <div className="bg-white border border-slate-200 rounded-xl shadow-sm overflow-hidden">
        <table className="min-w-full divide-y divide-slate-200">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Tracking #
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Carrier
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Status
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Order
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Shipped
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Delivered
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Link
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {loading && (
              <tr>
                <td
                  colSpan={7}
                  className="px-4 py-6 text-center text-sm text-slate-500"
                >
                  Loading…
                </td>
              </tr>
            )}
            {!loading && shipments.length === 0 && (
              <tr>
                <td
                  colSpan={7}
                  className="px-4 py-6 text-center text-sm text-slate-500"
                >
                  No shipments yet.
                </td>
              </tr>
            )}
            {shipments.map((f) => (
              <tr key={f.id} className="hover:bg-slate-50">
                <td className="px-4 py-3 text-sm font-mono text-slate-900">
                  {f.tracking_number || "—"}
                </td>
                <td className="px-4 py-3 text-sm text-slate-600 capitalize">
                  {f.carrier || "—"}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[f.status] || "bg-slate-100 text-slate-600 ring-slate-500/20"}`}
                  >
                    {f.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-600 font-mono text-xs">
                  {f.order_id.slice(0, 8)}…
                </td>
                <td className="px-4 py-3 text-sm text-slate-600">
                  {f.shipped_at
                    ? new Date(f.shipped_at).toLocaleDateString()
                    : "—"}
                </td>
                <td className="px-4 py-3 text-sm text-slate-600">
                  {f.delivered_at
                    ? new Date(f.delivered_at).toLocaleDateString()
                    : "—"}
                </td>
                <td className="px-4 py-3 text-sm">
                  {f.tracking_url ? (
                    <a
                      href={f.tracking_url}
                      target="_blank"
                      rel="noreferrer"
                      className="text-indigo-600 hover:underline"
                    >
                      Track →
                    </a>
                  ) : (
                    "—"
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {pages > 1 && (
        <div className="mt-4 flex items-center justify-between text-sm text-slate-600">
          <div>
            Page {page} of {pages}
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="px-3 py-1 border border-slate-300 rounded-md disabled:opacity-40"
            >
              Prev
            </button>
            <button
              onClick={() => setPage((p) => Math.min(pages, p + 1))}
              disabled={page === pages}
              className="px-3 py-1 border border-slate-300 rounded-md disabled:opacity-40"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
