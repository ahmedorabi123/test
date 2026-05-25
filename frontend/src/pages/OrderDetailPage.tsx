import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  ordersApi,
  type Order,
  type OrderStockAllocationLine,
  type OrderTimelineEntry,
} from "../api/orders";
import DeliveryActions from "../components/shipments/DeliveryActions";

const STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  processing: "bg-blue-50 text-blue-700 ring-blue-600/20",
  fulfilled: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  cancelled: "bg-gray-100 text-gray-600 ring-gray-500/20",
  refunded: "bg-rose-50 text-rose-700 ring-rose-600/20",
};

const FIN_STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  authorized: "bg-sky-50 text-sky-700 ring-sky-600/20",
  paid: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  partially_refunded: "bg-purple-50 text-purple-700 ring-purple-600/20",
  refunded: "bg-rose-50 text-rose-700 ring-rose-600/20",
  voided: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

function Badge({ value, map }: { value: string; map: Record<string, string> }) {
  return (
    <span
      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
        map[value] ?? "bg-gray-100 text-gray-600 ring-gray-500/20"
      }`}
    >
      {value.replace(/_/g, " ")}
    </span>
  );
}

function formatMoney(val: string | number | undefined, currency = "USD") {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(Number(val ?? 0));
}

function timelineTitle(entry: OrderTimelineEntry) {
  const type = entry.type.replace(/[._]/g, " ");
  return type.charAt(0).toUpperCase() + type.slice(1);
}

function timelineSummary(entry: OrderTimelineEntry) {
  const payload = entry.payload ?? {};
  const trackingCompany = payload.tracking_company;
  const trackingNumber = payload.tracking_number;
  const deliveryStatus = payload.delivery_status;
  const amount = payload.amount;
  const currency = payload.currency;
  const reason = payload.reason;

  if (trackingCompany || trackingNumber || deliveryStatus) {
    return [trackingCompany, trackingNumber, deliveryStatus]
      .filter((v) => typeof v === "string" && v.length > 0)
      .join(" · ");
  }

  if (amount && typeof amount === "string") {
    return `${formatMoney(amount, typeof currency === "string" ? currency : "USD")}${
      typeof reason === "string" && reason.length > 0 ? ` · ${reason}` : ""
    }`;
  }

  return "";
}

export default function OrderDetailPage() {
  const { id } = useParams<{ id: string }>();

  const [order, setOrder] = useState<Order | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [transitioning, setTransitioning] = useState(false);
  const [allocations, setAllocations] = useState<OrderStockAllocationLine[]>(
    [],
  );
  const [timeline, setTimeline] = useState<OrderTimelineEntry[]>([]);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    Promise.all([
      ordersApi.get(id),
      ordersApi.stockAllocation(id),
      ordersApi.timeline(id),
    ])
      .then(([orderRow, allocationRows, timelineRows]) => {
        setOrder(orderRow);
        setAllocations(allocationRows);
        setTimeline(timelineRows);
      })
      .catch((e) => setError((e as Error).message || "Failed to load order"))
      .finally(() => setLoading(false));
  }, [id]);

  const reloadOrder = () => {
    if (!order) return;
    Promise.all([
      ordersApi.get(order.id),
      ordersApi.stockAllocation(order.id),
      ordersApi.timeline(order.id),
    ]).then(([orderRow, allocationRows, timelineRows]) => {
      setOrder(orderRow);
      setAllocations(allocationRows);
      setTimeline(timelineRows);
    });
  };

  const transition = async (to: string, confirmMsg?: string) => {
    if (!order) return;
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    setTransitioning(true);
    try {
      const updated = await ordersApi.transition(order.id, to);
      setOrder(updated);
      ordersApi.stockAllocation(order.id).then(setAllocations);
    } catch (e) {
      const err = e as {
        response?: { data?: { error?: { message?: string } } };
        message?: string;
      };
      alert(
        err.response?.data?.error?.message ||
          err.message ||
          "Transition failed",
      );
    } finally {
      setTransitioning(false);
    }
  };

  // Compute legal next states (mirrors OrderStateMachine)
  const legalStatus: Record<string, string[]> = {
    pending: ["processing", "fulfilled", "cancelled"],
    processing: ["fulfilled", "cancelled"],
    fulfilled: [],
    cancelled: [],
    refunded: [],
  };
  const legalManualStatus: Record<string, string[]> = {
    pending: ["fulfilled", "cancelled"],
    processing: ["fulfilled", "cancelled"],
    fulfilled: [],
    cancelled: [],
    refunded: [],
  };
  const legalFinancial: Record<string, string[]> = {
    pending: ["authorized", "paid", "voided"],
    authorized: ["paid", "voided"],
    paid: [],
    partially_refunded: [],
    refunded: [],
    voided: [],
  };
  const legalManualFinancial: Record<string, string[]> = {
    pending: ["paid", "voided"],
    authorized: ["paid", "voided"],
    paid: [],
    partially_refunded: [],
    refunded: [],
    voided: [],
  };
  const STATUS_LABEL: Record<string, string> = {
    processing: "Start processing",
    fulfilled: "Mark as fulfilled",
    cancelled: "Cancel order",
    authorized: "Mark as authorized",
    paid: "Mark as paid",
    voided: "Void payment",
  };

  if (loading)
    return <div className="p-6 text-sm text-slate-500">Loading order…</div>;
  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!order) return null;
  const isReadOnly = Boolean(
    order.read_only_origin ||
    order.source === "shopify" ||
    order.shopify_order_id,
  );
  const isManualOrder =
    order.source === "manual" || order.source === "showroom";
  const statusMap = isManualOrder ? legalManualStatus : legalStatus;
  const financialMap = isManualOrder ? legalManualFinancial : legalFinancial;
  const statusTargets = isReadOnly ? [] : (statusMap[order.status] ?? []);
  const financialTargets = isReadOnly
    ? []
    : (financialMap[order.financial_status] ?? []);

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Link
              to="/orders"
              className="text-sm text-slate-500 hover:text-slate-700"
            >
              ← Orders
            </Link>
          </div>
          <h1 className="text-2xl font-semibold text-slate-900 mt-1 font-mono">
            {order.order_number}
          </h1>
          {order.external_number && (
            <div className="text-xs text-slate-500 mt-0.5">
              External: {order.external_number}
            </div>
          )}
          <div className="flex items-center gap-2 mt-2">
            <Badge value={order.status} map={STATUS_STYLES} />
            <Badge value={order.financial_status} map={FIN_STATUS_STYLES} />
            <span className="text-xs text-slate-500 uppercase tracking-wide">
              {order.source}
            </span>
            {order.risk_level && order.risk_level !== "low" && (
              <span className="inline-flex items-center rounded-md bg-rose-50 text-rose-700 ring-1 ring-inset ring-rose-600/20 px-2 py-0.5 text-xs font-medium">
                {order.risk_level} risk
              </span>
            )}
          </div>
          {order.tags && order.tags.length > 0 && (
            <div className="flex flex-wrap gap-1 mt-2">
              {order.tags.map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-700"
                >
                  {t}
                </span>
              ))}
            </div>
          )}
        </div>
        <div className="flex items-center gap-2">
          {statusTargets.map((next) => (
            <button
              key={`s-${next}`}
              onClick={() =>
                transition(
                  next,
                  next === "cancelled"
                    ? `Cancel order ${order.order_number}?`
                    : undefined,
                )
              }
              disabled={transitioning}
              className={
                next === "cancelled"
                  ? "px-3 py-2 text-sm border border-rose-200 text-rose-700 rounded-lg hover:bg-rose-50 disabled:opacity-60"
                  : "px-3 py-2 text-sm border border-slate-200 text-slate-700 rounded-lg hover:bg-slate-50 disabled:opacity-60"
              }
            >
              {STATUS_LABEL[next] ?? next}
            </button>
          ))}
          {financialTargets.map((next) => (
            <button
              key={`f-${next}`}
              onClick={() => transition(next)}
              disabled={transitioning}
              className="px-3 py-2 text-sm border border-emerald-200 text-emerald-700 rounded-lg hover:bg-emerald-50 disabled:opacity-60"
            >
              {STATUS_LABEL[next] ?? next}
            </button>
          ))}
          <Link
            to="/orders/new"
            className="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
          >
            New order
          </Link>
        </div>
      </div>

      {isReadOnly && (
        <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
          This order is managed by Shopify. Customer, item, and fulfillment
          details are read-only in the ERP.
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Totals card */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Totals
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-slate-600">Subtotal</span>
            <span>{formatMoney(order.subtotal_price, order.currency)}</span>
          </div>
          {Number(order.total_shipping) > 0 && (
            <div className="flex justify-between text-sm">
              <span className="text-slate-600">Shipping</span>
              <span>{formatMoney(order.total_shipping, order.currency)}</span>
            </div>
          )}
          {Number(order.total_tax) > 0 && (
            <div className="flex justify-between text-sm">
              <span className="text-slate-600">Tax</span>
              <span>{formatMoney(order.total_tax, order.currency)}</span>
            </div>
          )}
          {Number(order.total_discount) > 0 && (
            <div className="flex justify-between text-sm text-rose-600">
              <span>Discount</span>
              <span>−{formatMoney(order.total_discount, order.currency)}</span>
            </div>
          )}
          <div className="flex justify-between text-sm font-semibold border-t border-slate-200 pt-2">
            <span>Total</span>
            <span>{formatMoney(order.total_price, order.currency)}</span>
          </div>
          {order.total_outstanding && Number(order.total_outstanding) > 0 && (
            <div className="flex justify-between text-xs text-amber-700 pt-1">
              <span>Outstanding</span>
              <span>
                {formatMoney(order.total_outstanding, order.currency)}
              </span>
            </div>
          )}
          {order.payment_gateway_names &&
            order.payment_gateway_names.length > 0 && (
              <div className="text-xs text-slate-500 pt-1">
                via {order.payment_gateway_names.join(", ")}
              </div>
            )}
        </div>

        {/* Customer card */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-1">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Customer
          </div>
          {order.customer_name ? (
            <div className="text-sm font-medium text-slate-900">
              {order.customer_name}
            </div>
          ) : (
            <div className="text-sm text-slate-400 italic">Guest</div>
          )}
          {order.customer_email && (
            <div className="text-sm text-slate-600">{order.customer_email}</div>
          )}
          {order.notes && (
            <div className="mt-2 text-xs text-slate-500 bg-slate-50 rounded p-2">
              {order.notes}
            </div>
          )}
        </div>

        {/* Dates card */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-1">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Delivery
          </div>
          <div className="text-sm text-slate-700">
            {order.delivery_method || "—"}
          </div>
          {order.delivery_status && (
            <div className="text-xs capitalize text-slate-500">
              Status: {order.delivery_status.replace(/_/g, " ")}
            </div>
          )}
          <div className="text-xs text-slate-500">
            {order.items_count ?? 0} item
            {(order.items_count ?? 0) === 1 ? "" : "s"}
          </div>
        </div>

        {/* Dates card */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-1">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Dates
          </div>
          <div className="text-sm text-slate-600">
            <span className="font-medium">Placed:</span>{" "}
            {new Date(order.placed_at).toLocaleString()}
          </div>
          {order.cancelled_at && (
            <div className="text-sm text-rose-600">
              <span className="font-medium">Cancelled:</span>{" "}
              {new Date(order.cancelled_at).toLocaleString()}
              {order.cancel_reason && ` (${order.cancel_reason})`}
            </div>
          )}
          {order.closed_at && (
            <div className="text-sm text-slate-600">
              <span className="font-medium">Closed:</span>{" "}
              {new Date(order.closed_at).toLocaleString()}
            </div>
          )}
          <div className="text-sm text-slate-600">
            <span className="font-medium">Created:</span>{" "}
            {new Date(order.created_at).toLocaleString()}
          </div>
        </div>
      </div>

      {/* Line items */}
      <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-200">
          <h2 className="text-sm font-semibold text-slate-900">Line items</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-[720px] text-sm">
            <thead className="bg-slate-50 text-xs text-slate-500 uppercase">
              <tr>
                <th className="px-4 py-2 text-left">Product / SKU</th>
                <th className="px-4 py-2 text-right">Qty</th>
                <th className="px-4 py-2 text-right">Price</th>
                <th className="px-4 py-2 text-right">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(order.line_items ?? []).map((li) => (
                <tr key={li.id}>
                  <td className="px-4 py-3">
                    <div className="font-medium text-slate-900">{li.title}</div>
                    {li.variant_title && (
                      <div className="text-xs text-slate-500">
                        {li.variant_title}
                      </div>
                    )}
                    {li.sku && (
                      <div className="text-xs text-slate-400 font-mono">
                        {li.sku}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    {li.quantity}
                    <div className="text-xs text-slate-400">
                      {li.fulfilled_quantity ?? 0} fulfilled
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    {formatMoney(li.price, order.currency)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-medium">
                    {formatMoney(li.line_total, order.currency)}
                  </td>
                </tr>
              ))}
              {!order.line_items?.length && (
                <tr>
                  <td
                    colSpan={4}
                    className="px-4 py-4 text-center text-slate-400"
                  >
                    No line items
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {allocations.length > 0 && (
        <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
          <div className="px-4 py-3 border-b border-slate-200">
            <h2 className="text-sm font-semibold text-slate-900">
              Stock allocation
            </h2>
          </div>
          <div className="divide-y divide-slate-100">
            {allocations.map((line) => {
              const fulfilled = line.fulfilled_quantity ?? 0;
              const reserved = line.reserved_quantity ?? 0;
              const progress = Math.min(
                100,
                Math.round(
                  ((fulfilled + reserved) / Math.max(line.quantity, 1)) * 100,
                ),
              );
              return (
                <div key={line.id} className="px-4 py-3">
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <div className="text-sm font-medium text-slate-900">
                        {line.title}
                      </div>
                      <div className="text-xs text-slate-500">
                        {fulfilled} fulfilled · {reserved} reserved ·{" "}
                        {line.quantity} ordered
                      </div>
                    </div>
                    <div className="w-full pt-1 sm:w-40">
                      <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                        <div
                          className="h-full bg-emerald-500"
                          style={{ width: `${progress}%` }}
                        />
                      </div>
                    </div>
                  </div>
                  <div className="mt-2 grid grid-cols-1 gap-2 md:grid-cols-2">
                    {line.allocations.map((allocation) => (
                      <div
                        key={allocation.id}
                        className="rounded-lg border border-slate-200 px-3 py-2 text-xs"
                      >
                        <div className="flex items-center justify-between">
                          <span className="font-medium text-slate-700">
                            {allocation.warehouse_name ||
                              allocation.warehouse_code ||
                              "Warehouse"}
                          </span>
                          <Badge
                            value={allocation.status}
                            map={STATUS_STYLES}
                          />
                        </div>
                        <div className="mt-1 text-slate-500">
                          {allocation.quantity} units · available{" "}
                          {allocation.available} · on hand {allocation.on_hand}
                        </div>
                      </div>
                    ))}
                    {line.allocations.length === 0 && (
                      <div className="text-xs text-slate-400">
                        No allocation rows
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Timeline */}
      <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-200">
          <h2 className="text-sm font-semibold text-slate-900">Timeline</h2>
        </div>
        <div className="divide-y divide-slate-100">
          {timeline.map((entry, index) => (
            <div
              key={`${entry.type}-${entry.occurred_at}-${index}`}
              className="px-4 py-3"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-sm font-medium text-slate-900">
                    {timelineTitle(entry)}
                  </div>
                  {timelineSummary(entry) && (
                    <div className="text-xs text-slate-500 mt-0.5">
                      {timelineSummary(entry)}
                    </div>
                  )}
                </div>
                <div className="text-xs text-slate-400 whitespace-nowrap">
                  {entry.occurred_at
                    ? new Date(entry.occurred_at).toLocaleString()
                    : "—"}
                </div>
              </div>
            </div>
          ))}
          {timeline.length === 0 && (
            <div className="px-4 py-4 text-sm text-slate-400">
              No timeline events yet
            </div>
          )}
        </div>
      </div>

      {/* Fulfillments */}
      {(order.fulfillments ?? []).length > 0 && (
        <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
          <div className="px-4 py-3 border-b border-slate-200">
            <h2 className="text-sm font-semibold text-slate-900">
              Fulfillments
            </h2>
          </div>
          <div className="divide-y divide-slate-100">
            {(order.fulfillments ?? []).map((f) => (
              <div key={f.id} className="px-4 py-3 text-sm">
                <div className="flex items-center justify-between">
                  <Link
                    to={`/shipments/${f.id}`}
                    className="font-medium font-mono text-indigo-700 hover:underline"
                  >
                    {f.tracking_number ?? "—"}
                  </Link>
                  <Badge value={f.status} map={STATUS_STYLES} />
                </div>
                <div className="mt-1 flex items-center justify-between gap-3">
                  <div className="text-xs text-slate-500">
                    {f.carrier && <span>{f.carrier}</span>}
                    {f.delivery_status && (
                      <span className="ml-2 capitalize">
                        · {f.delivery_status.replace(/_/g, " ")}
                      </span>
                    )}
                  </div>
                  <DeliveryActions
                    fulfillment={f}
                    onUpdated={reloadOrder}
                    size="sm"
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="pb-10" />
    </div>
  );
}
