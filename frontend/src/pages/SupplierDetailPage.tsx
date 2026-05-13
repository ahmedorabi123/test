import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { PurchaseOrder } from "../api/purchaseOrders";
import { suppliersApi, type Supplier } from "../api/suppliers";

type Tab = "overview" | "purchase_orders" | "activity";

function formatMoney(value: string | number | undefined, currency = "EGP") {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(Number(value ?? 0));
}

function statusClass(status: string) {
  if (status === "active")
    return "bg-emerald-50 text-emerald-700 ring-emerald-600/20";
  if (status === "on_hold")
    return "bg-amber-50 text-amber-700 ring-amber-600/20";
  return "bg-gray-100 text-gray-600 ring-gray-500/20";
}

function textValue(record: Record<string, unknown> | undefined, key: string) {
  const value = record?.[key];
  return typeof value === "string" && value.trim() ? value : null;
}

export default function SupplierDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [supplier, setSupplier] = useState<Supplier | null>(null);
  const [purchaseOrders, setPurchaseOrders] = useState<PurchaseOrder[]>([]);
  const [tab, setTab] = useState<Tab>("overview");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    Promise.all([suppliersApi.get(id), suppliersApi.purchaseOrders(id)])
      .then(([supplierRow, poRows]) => {
        setSupplier(supplierRow);
        setPurchaseOrders(poRows);
      })
      .catch((err) =>
        setError((err as Error).message || "Failed to load supplier"),
      )
      .finally(() => setLoading(false));
  }, [id]);

  const addressLines = useMemo(() => {
    const address = supplier?.address;
    return [
      textValue(address, "line1"),
      textValue(address, "line2"),
      [textValue(address, "city"), textValue(address, "governorate")]
        .filter(Boolean)
        .join(", "),
      textValue(address, "country"),
    ].filter(Boolean);
  }, [supplier]);

  if (loading)
    return (
      <div className="p-6 text-sm text-slate-500">Loading supplier...</div>
    );
  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!supplier) return null;

  const summary = supplier.balance_summary;
  const terms = supplier.payment_terms;

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <Link
            to="/suppliers"
            className="text-sm text-slate-500 hover:text-slate-700"
          >
            Back to suppliers
          </Link>
          <div className="mt-1 flex items-center gap-2">
            <h1 className="text-2xl font-semibold text-slate-900">
              {supplier.name}
            </h1>
            {supplier.supplier_code && (
              <span className="rounded bg-slate-100 px-2 py-1 text-xs font-mono text-slate-600">
                {supplier.supplier_code}
              </span>
            )}
          </div>
          <div className="mt-2 flex items-center gap-2">
            <span
              className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium capitalize ring-1 ring-inset ${statusClass(
                supplier.status,
              )}`}
            >
              {supplier.status.replace("_", " ")}
            </span>
            <span className="text-xs text-slate-500">{supplier.currency}</span>
          </div>
        </div>
        <Link
          to="/suppliers/new"
          className="rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          New supplier
        </Link>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <SummaryCard
          label="Open balance"
          value={formatMoney(summary?.open_total, supplier.currency)}
        />
        <SummaryCard
          label="Total ordered"
          value={formatMoney(summary?.total_ordered, supplier.currency)}
        />
        <SummaryCard
          label="Received"
          value={formatMoney(summary?.received_total, supplier.currency)}
        />
        <SummaryCard
          label="POs"
          value={String(
            summary?.purchase_orders_count ?? purchaseOrders.length,
          )}
        />
      </div>

      <div className="border-b border-slate-200">
        <nav className="flex gap-4 text-sm">
          {[
            ["overview", "Overview"],
            ["purchase_orders", "Purchase orders"],
            ["activity", "Activity"],
          ].map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => setTab(value as Tab)}
              className={`border-b-2 px-1 py-2 font-medium ${
                tab === value
                  ? "border-indigo-600 text-indigo-700"
                  : "border-transparent text-slate-500 hover:text-slate-700"
              }`}
            >
              {label}
            </button>
          ))}
        </nav>
      </div>

      {tab === "overview" && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <section className="rounded-xl border border-slate-200 bg-white p-4 space-y-3">
            <h2 className="text-sm font-semibold text-slate-900">Contact</h2>
            <Info label="Email" value={supplier.email || "-"} />
            <Info label="Phone" value={supplier.phone || "-"} />
            <Info label="Tax ID" value={supplier.tax_id || "-"} />
            <Info
              label="Lead time"
              value={
                supplier.lead_time_days
                  ? `${supplier.lead_time_days} days`
                  : "-"
              }
            />
          </section>
          <section className="rounded-xl border border-slate-200 bg-white p-4 space-y-3">
            <h2 className="text-sm font-semibold text-slate-900">Address</h2>
            {addressLines.length > 0 ? (
              <div className="text-sm text-slate-700 space-y-1">
                {addressLines.map((line) => (
                  <div key={line}>{line}</div>
                ))}
              </div>
            ) : (
              <div className="text-sm text-slate-400">-</div>
            )}
          </section>
          <section className="rounded-xl border border-slate-200 bg-white p-4 space-y-3">
            <h2 className="text-sm font-semibold text-slate-900">Payment</h2>
            <Info label="Net days" value={String(terms?.net_days ?? "-")} />
            <Info
              label="Notes"
              value={typeof terms?.notes === "string" ? terms.notes : "-"}
            />
          </section>
          {supplier.notes && (
            <section className="rounded-xl border border-slate-200 bg-white p-4 lg:col-span-3">
              <h2 className="text-sm font-semibold text-slate-900 mb-2">
                Notes
              </h2>
              <div className="whitespace-pre-wrap text-sm text-slate-700">
                {supplier.notes}
              </div>
            </section>
          )}
        </div>
      )}

      {tab === "purchase_orders" && (
        <section className="overflow-hidden rounded-xl border border-slate-200 bg-white">
          <div className="overflow-x-auto">
            <table className="min-w-[680px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-slate-500">
                <tr>
                  <th className="px-4 py-2 text-left">PO</th>
                  <th className="px-4 py-2 text-left">Warehouse</th>
                  <th className="px-4 py-2 text-left">Status</th>
                  <th className="px-4 py-2 text-right">Total</th>
                  <th className="px-4 py-2 text-left">Expected</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {purchaseOrders.map((po) => (
                  <tr key={po.id}>
                    <td className="px-4 py-2">
                      <Link
                        to={`/purchases/${po.id}`}
                        className="font-mono text-indigo-700 hover:underline"
                      >
                        {po.po_number}
                      </Link>
                    </td>
                    <td className="px-4 py-2 text-slate-600">
                      {po.warehouse_name || "-"}
                    </td>
                    <td className="px-4 py-2 capitalize text-slate-700">
                      {po.status}
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">
                      {formatMoney(po.total, po.currency)}
                    </td>
                    <td className="px-4 py-2 text-slate-600">
                      {po.expected_at
                        ? new Date(po.expected_at).toLocaleDateString()
                        : "-"}
                    </td>
                  </tr>
                ))}
                {purchaseOrders.length === 0 && (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-4 py-4 text-center text-slate-400"
                    >
                      No purchase orders
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab === "activity" && (
        <section className="rounded-xl border border-slate-200 bg-white divide-y divide-slate-100">
          <ActivityItem label="Supplier created" at={supplier.created_at} />
          <ActivityItem label="Supplier updated" at={supplier.updated_at} />
          {purchaseOrders.slice(0, 8).map((po) => (
            <ActivityItem
              key={po.id}
              label={`PO ${po.po_number} ${po.status}`}
              at={po.updated_at}
            />
          ))}
        </section>
      )}
    </div>
  );
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
        {label}
      </div>
      <div className="mt-1 text-lg font-semibold text-slate-900">{value}</div>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-slate-500">{label}</div>
      <div className="text-sm text-slate-900">{value}</div>
    </div>
  );
}

function ActivityItem({ label, at }: { label: string; at?: string | null }) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
      <div className="font-medium text-slate-800">{label}</div>
      <div className="text-xs text-slate-500">
        {at ? new Date(at).toLocaleString() : "-"}
      </div>
    </div>
  );
}
