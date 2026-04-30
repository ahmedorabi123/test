import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { customersApi, type Customer } from "../api/customers";

function formatMoney(val: string | number | undefined, currency = "USD") {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(Number(val ?? 0));
}

export default function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [customer, setCustomer] = useState<Customer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    customersApi
      .get(id)
      .then(setCustomer)
      .catch((e) => setError((e as Error).message || "Failed to load customer"))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading)
    return <div className="p-6 text-sm text-slate-500">Loading customer…</div>;
  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!customer) return null;

  const a = customer.default_address || {};

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <Link
            to="/customers"
            className="text-sm text-slate-500 hover:text-slate-700"
          >
            ← Customers
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 mt-1">
            {customer.display_name || customer.email || "Customer"}
          </h1>
          <div className="flex items-center gap-2 mt-2">
            {customer.shopify_customer_id ? (
              <span className="inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
                Shopify customer
              </span>
            ) : (
              <span className="inline-flex items-center rounded-full bg-slate-100 text-slate-600 ring-1 ring-inset ring-slate-500/20 px-2 py-0.5 text-xs font-medium">
                Manual
              </span>
            )}
            {customer.accepts_marketing && (
              <span className="inline-flex items-center rounded-md bg-indigo-50 text-indigo-700 ring-1 ring-inset ring-indigo-600/20 px-2 py-0.5 text-xs font-medium">
                Subscribed to marketing
              </span>
            )}
            {customer.verified_email && (
              <span className="inline-flex items-center rounded-md bg-sky-50 text-sky-700 ring-1 ring-inset ring-sky-600/20 px-2 py-0.5 text-xs font-medium">
                Verified email
              </span>
            )}
            {customer.state && (
              <span className="text-xs text-slate-500 capitalize">
                {customer.state}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <StatCard label="Orders" value={String(customer.orders_count ?? 0)} />
        <StatCard
          label="Amount spent"
          value={formatMoney(customer.total_spent, customer.currency)}
        />
        <StatCard
          label="Avg. order value"
          value={
            customer.orders_count
              ? formatMoney(
                  Number(customer.total_spent) / customer.orders_count,
                  customer.currency,
                )
              : "—"
          }
        />
        <StatCard
          label="Last order"
          value={
            customer.last_order_at
              ? new Date(customer.last_order_at).toLocaleDateString()
              : "—"
          }
          sub={customer.last_order_name || undefined}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Contact */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Contact
          </div>
          <div className="text-sm text-slate-900">{customer.email || "—"}</div>
          <div className="text-sm text-slate-600">{customer.phone || "—"}</div>
        </div>

        {/* Default address */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-1 md:col-span-2">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Default address
          </div>
          {Object.keys(a).length > 0 ? (
            <div className="text-sm text-slate-700 leading-6">
              {[
                a.address1,
                a.address2,
                [a.city, a.province, a.zip].filter(Boolean).join(", "),
                a.country,
              ]
                .filter(Boolean)
                .map((line, i) => (
                  <div key={i}>{line as string}</div>
                ))}
            </div>
          ) : (
            <div className="text-sm text-slate-400">No address on file</div>
          )}
        </div>
      </div>

      {/* Tags + Note */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Tags
          </div>
          {customer.tags && customer.tags.length > 0 ? (
            <div className="flex flex-wrap gap-1">
              {customer.tags.map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                >
                  {t}
                </span>
              ))}
            </div>
          ) : (
            <div className="text-sm text-slate-400">No tags</div>
          )}
        </div>
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
          <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
            Note
          </div>
          <div className="text-sm text-slate-700 whitespace-pre-wrap">
            {customer.note || <span className="text-slate-400">No note</span>}
          </div>
        </div>
      </div>

      {/* All addresses */}
      {customer.addresses && customer.addresses.length > 1 && (
        <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
          <div className="px-4 py-3 border-b border-slate-200 text-sm font-semibold text-slate-900">
            All addresses ({customer.addresses.length})
          </div>
          <div className="divide-y divide-slate-100">
            {customer.addresses.map((addr, idx) => (
              <div key={idx} className="px-4 py-3 text-sm text-slate-700">
                {[
                  addr.address1,
                  addr.city,
                  addr.province,
                  addr.country,
                  addr.zip,
                ]
                  .filter(Boolean)
                  .join(", ")}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recent orders */}
      <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-200 text-sm font-semibold text-slate-900">
          Recent orders
        </div>
        {customer.orders && customer.orders.length > 0 ? (
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-xs text-slate-500 uppercase">
              <tr>
                <th className="px-4 py-2 text-left">Order</th>
                <th className="px-4 py-2 text-left">Date</th>
                <th className="px-4 py-2 text-left">Payment</th>
                <th className="px-4 py-2 text-left">Fulfillment</th>
                <th className="px-4 py-2 text-right">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {customer.orders.map((o) => (
                <tr key={o.id} className="hover:bg-slate-50">
                  <td className="px-4 py-2">
                    <Link
                      to={`/orders/${o.id}`}
                      className="font-mono text-indigo-700 hover:underline"
                    >
                      {o.order_number}
                    </Link>
                  </td>
                  <td className="px-4 py-2 text-slate-600">
                    {new Date(o.placed_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-2 capitalize text-slate-600">
                    {o.financial_status.replace("_", " ")}
                  </td>
                  <td className="px-4 py-2 capitalize text-slate-600">
                    {o.status}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums font-medium">
                    {formatMoney(o.total_price, customer.currency)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <div className="px-4 py-6 text-center text-sm text-slate-400">
            No orders yet
          </div>
        )}
      </div>

      <div className="pb-10" />
    </div>
  );
}

function StatCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="bg-white border border-slate-200 rounded-xl p-4">
      <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
        {label}
      </div>
      <div className="text-xl font-semibold text-slate-900 mt-1">{value}</div>
      {sub && <div className="text-xs text-slate-500 mt-0.5">{sub}</div>}
    </div>
  );
}
