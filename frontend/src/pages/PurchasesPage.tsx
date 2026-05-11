import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { purchaseOrdersApi, type PurchaseOrder } from "../api/purchaseOrders";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";

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
    <PageContainer className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-semibold">Purchase Orders</h1>
        <Link
          to="/purchases/new"
          className="inline-flex min-h-11 items-center justify-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + New PO
        </Link>
      </div>

      <div className="flex gap-2">
        <select
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setPage(1);
          }}
          className="min-h-11 rounded border border-slate-300 px-3 text-sm"
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

      <div className="space-y-3 md:hidden">
        {pos.map((po) => (
          <MobileRowCard
            key={po.id}
            title={<span className="font-mono text-sm text-slate-900">{po.po_number}</span>}
            subtitle={po.supplier_name}
            meta={`${po.currency} ${Number(po.total).toFixed(2)}`}
            fields={[
              { label: "Warehouse", value: po.warehouse_name || "-" },
              {
                label: "Status",
                value: (
                  <span
                    className={`inline-block rounded px-2 py-0.5 text-xs ${STATUS_STYLES[po.status]}`}
                  >
                    {po.status}
                  </span>
                ),
              },
              {
                label: "Expected",
                value: po.expected_at ? new Date(po.expected_at).toLocaleDateString() : "-",
              },
            ]}
            actions={
              <Link
                to={`/purchases/${po.id}`}
                className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
              >
                Open purchase
              </Link>
            }
          />
        ))}
        {!loading && pos.length === 0 && (
          <div className="rounded-lg border border-slate-200 bg-white px-4 py-8 text-center text-sm text-slate-500">
            No purchase orders yet.
          </div>
        )}
      </div>

      <div className="hidden overflow-x-auto rounded bg-white shadow md:block">
        <table className="min-w-[720px] text-sm">
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

      <div className="flex flex-col gap-3 text-sm sm:flex-row sm:items-center sm:justify-between">
        <span>Total: {total}</span>
        <div className="flex items-center gap-2">
          <button
            disabled={page <= 1}
            onClick={() => setPage((p) => p - 1)}
            className="min-h-10 rounded border px-3 disabled:opacity-50"
          >
            Prev
          </button>
          <span className="min-h-10 px-2 leading-10">
            Page {page} / {pages}
          </span>
          <button
            disabled={page >= pages}
            onClick={() => setPage((p) => p + 1)}
            className="min-h-10 rounded border px-3 disabled:opacity-50"
          >
            Next
          </button>
        </div>
      </div>
    </PageContainer>
  );
}
