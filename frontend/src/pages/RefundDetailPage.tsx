import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { refundsApi, type Refund } from "../api/refunds";

function formatDate(value?: string | null) {
  return value ? new Date(value).toLocaleString() : "-";
}

export default function RefundDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [refund, setRefund] = useState<Refund | null>(null);
  const [transitioning, setTransitioning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    refundsApi
      .get(id)
      .then(setRefund)
      .catch((e) => setError((e as Error).message || "Failed to load refund"));
  }, [id]);

  async function transition(to: string) {
    if (!refund) return;
    setTransitioning(true);
    try {
      setRefund(
        to === "cancelled"
          ? await refundsApi.cancel(refund.id)
          : await refundsApi.transition(refund.id, to),
      );
    } catch (e) {
      setError((e as Error).message || "Transition failed");
    } finally {
      setTransitioning(false);
    }
  }

  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!refund)
    return <div className="p-6 text-sm text-slate-500">Loading refund...</div>;

  const canTransition =
    !refund.shopify_refund_id &&
    !["processed", "cancelled"].includes(refund.status || "processed");

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div className="flex flex-wrap items-start gap-3">
        <div className="flex-1">
          <Link
            to="/refunds"
            className="text-sm text-slate-500 hover:text-slate-700"
          >
            Back to Refunds
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 mt-1">
            {Number(refund.amount).toFixed(2)} {refund.currency}
          </h1>
          <div className="mt-2 flex flex-wrap gap-2 text-xs text-slate-600">
            <span className="rounded bg-slate-100 px-2 py-1 capitalize">
              {refund.status || "processed"}
            </span>
            <span className="rounded bg-slate-100 px-2 py-1 capitalize">
              {refund.kind || (refund.shopify_refund_id ? "shopify" : "manual")}
            </span>
            <span className="rounded bg-slate-100 px-2 py-1">
              {refund.full ? "Full" : "Partial"}
            </span>
          </div>
        </div>
        {canTransition && (
          <div className="flex gap-2">
            <button
              disabled={transitioning}
              onClick={() => transition("approved")}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
            >
              Approve
            </button>
            <button
              disabled={transitioning}
              onClick={() => transition("processed")}
              className="rounded-lg bg-indigo-600 px-3 py-2 text-sm text-white"
            >
              Process
            </button>
            <button
              disabled={transitioning}
              onClick={() => transition("cancelled")}
              className="rounded-lg border border-rose-300 px-3 py-2 text-sm text-rose-700"
            >
              Cancel
            </button>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <section className="bg-white rounded-xl border border-slate-200 p-4 lg:col-span-2">
          <h2 className="text-sm font-semibold text-slate-900 mb-3">Refund</h2>
          <dl className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
            <Info label="Reason" value={refund.reason || "-"} />
            <Info label="Processed" value={formatDate(refund.processed_at)} />
            <Info label="Restock" value={refund.restock ? "Yes" : "No"} />
            <Info
              label="Inventory restocked"
              value={refund.inventory_restocked ? "Yes" : "No"}
            />
            <Info
              label="Shopify refund"
              value={
                refund.shopify_refund_id
                  ? String(refund.shopify_refund_id)
                  : "Manual"
              }
              mono
            />
            <Info
              label="Content hash"
              value={refund.content_hash || "-"}
              mono
            />
          </dl>
          {refund.note && (
            <div className="mt-4 rounded-lg bg-slate-50 p-3 text-sm text-slate-700 whitespace-pre-wrap">
              {refund.note}
            </div>
          )}
        </section>
        <section className="bg-white rounded-xl border border-slate-200 p-4">
          <h2 className="text-sm font-semibold text-slate-900 mb-3">
            Order & customer
          </h2>
          {refund.order && (
            <Link
              to={`/orders/${refund.order.id}`}
              className="font-mono text-sm text-indigo-700 hover:underline"
            >
              {refund.order.order_number}
            </Link>
          )}
          <div className="mt-3 text-sm text-slate-700">
            {refund.customer?.name || refund.customer?.email || "-"}
          </div>
          <div className="text-xs text-slate-500">
            {refund.customer?.email || ""}
          </div>
          {refund.order && (
            <div className="mt-3 text-xs text-slate-500">
              Order total {Number(refund.order.total_price).toFixed(2)}{" "}
              {refund.order.currency}
            </div>
          )}
        </section>
      </div>

      <section className="bg-white rounded-xl border border-slate-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-200 text-sm font-semibold text-slate-900">
          Refunded items
        </div>
        <div className="overflow-x-auto">
        <table className="min-w-[640px] text-sm">
          <thead className="bg-slate-50 text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-2 text-left">Item</th>
              <th className="px-4 py-2 text-left">SKU</th>
              <th className="px-4 py-2 text-right">Qty</th>
              <th className="px-4 py-2 text-right">Subtotal</th>
              <th className="px-4 py-2 text-left">Restock</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {(refund.line_items || []).map((item) => (
              <tr key={item.id}>
                <td className="px-4 py-2">
                  {item.title || item.variant_title || "Item"}
                </td>
                <td className="px-4 py-2 font-mono text-xs text-slate-500">
                  {item.sku || "-"}
                </td>
                <td className="px-4 py-2 text-right">{item.quantity}</td>
                <td className="px-4 py-2 text-right">
                  {Number(item.subtotal).toFixed(2)}
                </td>
                <td className="px-4 py-2 capitalize">
                  {item.restock_type ||
                    (item.restock ? "return" : "no restock")}
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

function Info({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div>
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd
        className={`text-slate-900 ${mono ? "font-mono text-xs break-all" : ""}`}
      >
        {value}
      </dd>
    </div>
  );
}
