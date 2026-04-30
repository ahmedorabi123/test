import { useCallback, useEffect, useState } from "react";
import { refundsApi, type Refund } from "../api/refunds";
import ManualRefundButton from "../components/refunds/ManualRefundButton";

export default function RefundsPage() {
  const [refunds, setRefunds] = useState<Refund[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const perPage = 25;
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, meta } = await refundsApi.list({ page, per_page: perPage });
      setRefunds(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load refunds");
    } finally {
      setLoading(false);
    }
  }, [page]);

  useEffect(() => {
    load();
  }, [load]);

  const pages = Math.max(1, Math.ceil(total / perPage));

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-end justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Refunds</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total} refund{total === 1 ? "" : "s"} · Estebdal + Shopify-driven
          </p>
        </div>
        <ManualRefundButton onCreated={load} />
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
                Amount
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Type
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Order
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Reason
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Processed
              </th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                Source
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {loading && (
              <tr>
                <td
                  colSpan={6}
                  className="px-4 py-6 text-center text-sm text-slate-500"
                >
                  Loading…
                </td>
              </tr>
            )}
            {!loading && refunds.length === 0 && (
              <tr>
                <td
                  colSpan={6}
                  className="px-4 py-6 text-center text-sm text-slate-500"
                >
                  No refunds yet.
                </td>
              </tr>
            )}
            {refunds.map((r) => (
              <tr key={r.id} className="hover:bg-slate-50">
                <td className="px-4 py-3 text-sm font-medium text-slate-900">
                  {Number(r.amount).toFixed(2)} {r.currency}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
                      r.full
                        ? "bg-rose-50 text-rose-700 ring-rose-600/20"
                        : "bg-amber-50 text-amber-700 ring-amber-600/20"
                    }`}
                  >
                    {r.full ? "full" : "partial"}
                  </span>
                </td>
                <td className="px-4 py-3 text-xs font-mono text-slate-600">
                  {r.order_id.slice(0, 8)}…
                </td>
                <td className="px-4 py-3 text-sm text-slate-600">
                  {r.reason || "—"}
                </td>
                <td className="px-4 py-3 text-sm text-slate-600">
                  {r.processed_at
                    ? new Date(r.processed_at).toLocaleDateString()
                    : "—"}
                </td>
                <td className="px-4 py-3 text-xs">
                  {r.shopify_refund_id ? (
                    <span className="inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 font-medium">
                      Shopify
                    </span>
                  ) : (
                    <span className="inline-flex items-center rounded-full bg-slate-100 text-slate-600 ring-1 ring-inset ring-slate-500/20 px-2 py-0.5 font-medium">
                      Manual
                    </span>
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
