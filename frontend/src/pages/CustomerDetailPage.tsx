import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import {
  customersApi,
  type Customer,
  type CustomerAddress,
  type CustomerInput,
} from "../api/customers";

function formatMoney(val: string | number | undefined, currency = "USD") {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(Number(val ?? 0));
}

function toDraft(c: Customer): CustomerInput {
  return {
    email: c.email ?? "",
    phone: c.phone ?? "",
    first_name: c.first_name ?? "",
    last_name: c.last_name ?? "",
    accepts_marketing: !!c.accepts_marketing,
    tax_exempt: !!c.tax_exempt,
    currency: c.currency || "EGP",
    note: c.note ?? "",
    tags: [...(c.tags ?? [])],
    default_address: { ...(c.default_address ?? {}) },
  };
}

function isAddressEmpty(a: CustomerAddress | undefined) {
  if (!a) return true;
  return ![
    "address1",
    "address2",
    "city",
    "province",
    "country",
    "zip",
    "phone",
    "company",
  ].some(
    (k) => (a[k as keyof CustomerAddress] ?? "").toString().trim().length > 0,
  );
}

export default function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [customer, setCustomer] = useState<Customer | null>(null);
  const [draft, setDraft] = useState<CustomerInput | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tagInput, setTagInput] = useState("");

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    customersApi
      .get(id)
      .then((c) => {
        setCustomer(c);
        setDraft(toDraft(c));
      })
      .catch((e) => setError((e as Error).message || "Failed to load customer"))
      .finally(() => setLoading(false));
  }, [id]);

  const isDirty = useMemo(() => {
    if (!customer || !draft) return false;
    return JSON.stringify(draft) !== JSON.stringify(toDraft(customer));
  }, [customer, draft]);

  async function handleSave() {
    if (!customer || !draft) return;
    setSaving(true);
    setError(null);
    try {
      const updated = await customersApi.update(customer.id, draft);
      // Refresh to get embedded last_order/orders
      const fresh = await customersApi.get(customer.id);
      setCustomer(fresh);
      setDraft(toDraft(fresh));
      void updated;
    } catch (e) {
      setError((e as Error).message || "Failed to save customer");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!customer) return;
    if (!window.confirm("Delete this customer? This cannot be undone.")) return;

    setSaving(true);
    setError(null);
    try {
      await customersApi.destroy(customer.id);
      navigate("/customers");
    } catch (e) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        err.response?.data?.error?.detail ||
          err.message ||
          "Failed to delete customer",
      );
    } finally {
      setSaving(false);
    }
  }

  function handleDiscard() {
    if (!customer) return;
    setDraft(toDraft(customer));
    setError(null);
  }

  function patchDraft(p: Partial<CustomerInput>) {
    setDraft((d) => (d ? { ...d, ...p } : d));
  }

  function patchAddress(p: Partial<CustomerAddress>) {
    setDraft((d) =>
      d ? { ...d, default_address: { ...(d.default_address ?? {}), ...p } } : d,
    );
  }

  if (loading)
    return <div className="p-6 text-sm text-slate-500">Loading customer…</div>;
  if (!customer || !draft)
    return error ? (
      <div className="p-6 text-sm text-rose-600">{error}</div>
    ) : null;

  const lo = customer.last_order;

  return (
    <div className="pb-16 max-w-6xl mx-auto">
      {/* Sticky save bar */}
      {isDirty && (
        <div className="sticky top-0 z-30 bg-amber-50 border-b border-amber-200 shadow-sm">
          <div className="px-6 py-3 flex items-center justify-between">
            <div className="text-sm font-medium text-amber-900">
              Unsaved changes
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={handleDiscard}
                disabled={saving}
                className="px-3 py-1.5 rounded-md text-sm font-medium text-slate-700 hover:bg-amber-100 disabled:opacity-50"
              >
                Discard
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="px-4 py-1.5 rounded-md bg-slate-900 text-white text-sm font-medium hover:bg-slate-800 disabled:opacity-50"
              >
                {saving ? "Saving…" : "Save"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="p-6 space-y-6">
        {error && (
          <div className="rounded-md bg-rose-50 border border-rose-200 px-4 py-2 text-sm text-rose-700">
            {error}
          </div>
        )}

        {/* Header */}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
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
            <div className="flex flex-wrap items-center gap-2 mt-2">
              {customer.shopify_customer_id ? (
                <span className="inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
                  Shopify customer
                </span>
              ) : (
                <span className="inline-flex items-center rounded-full bg-slate-100 text-slate-600 ring-1 ring-inset ring-slate-500/20 px-2 py-0.5 text-xs font-medium">
                  Manual
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
          <button
            onClick={handleDelete}
            disabled={saving}
            className="self-start rounded-lg border border-rose-300 bg-rose-50 px-3 py-1.5 text-xs font-medium text-rose-700 hover:bg-rose-100 disabled:opacity-50"
          >
            Delete customer
          </button>
        </div>

        {/* Stats */}
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

        {/* Last order featured */}
        {lo && (
          <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
            <div className="flex flex-col gap-3 border-b border-slate-200 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm font-semibold text-slate-900">
                  Last order
                </span>
                <Link
                  to={`/orders/${lo.id}`}
                  className="font-mono text-indigo-700 hover:underline text-sm"
                >
                  {lo.order_number}
                </Link>
                <span className="text-xs text-slate-500">
                  {new Date(lo.placed_at).toLocaleString()}
                </span>
              </div>
              <div className="flex flex-wrap items-center gap-2 text-xs">
                <span className="rounded bg-slate-100 px-2 py-0.5 capitalize">
                  {lo.financial_status?.replace("_", " ")}
                </span>
                <span className="rounded bg-slate-100 px-2 py-0.5 capitalize">
                  {lo.fulfillment_status || lo.status || "—"}
                </span>
                <span className="font-semibold text-slate-900 text-sm">
                  {formatMoney(
                    lo.total_price,
                    lo.currency || customer.currency,
                  )}
                </span>
              </div>
            </div>
            {lo.line_items && lo.line_items.length > 0 && (
              <div className="overflow-x-auto">
                <table className="min-w-[680px] text-sm">
                  <thead className="bg-slate-50 text-xs text-slate-500 uppercase">
                    <tr>
                      <th className="px-4 py-2 text-left">Item</th>
                      <th className="px-4 py-2 text-left">SKU</th>
                      <th className="px-4 py-2 text-right">Qty</th>
                      <th className="px-4 py-2 text-right">Price</th>
                      <th className="px-4 py-2 text-right">Total</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {lo.line_items.map((li) => (
                      <tr key={li.id}>
                        <td className="px-4 py-2">
                          <div className="font-medium text-slate-900">
                            {li.title}
                          </div>
                          {li.variant_title && (
                            <div className="text-xs text-slate-500">
                              {li.variant_title}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-2 text-slate-600 font-mono text-xs">
                          {li.sku || "—"}
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums">
                          {li.quantity}
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums">
                          {formatMoney(
                            li.price,
                            lo.currency || customer.currency,
                          )}
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums font-medium">
                          {formatMoney(
                            li.line_total,
                            lo.currency || customer.currency,
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* Editable: Customer overview */}
        <Section title="Customer">
          <Field label="First name">
            <input
              type="text"
              value={draft.first_name ?? ""}
              onChange={(e) => patchDraft({ first_name: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
            />
          </Field>
          <Field label="Last name">
            <input
              type="text"
              value={draft.last_name ?? ""}
              onChange={(e) => patchDraft({ last_name: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
            />
          </Field>
          <Field label="Email">
            <input
              type="email"
              value={draft.email ?? ""}
              onChange={(e) => patchDraft({ email: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
            />
          </Field>
          <Field label="Phone">
            <input
              type="tel"
              value={draft.phone ?? ""}
              onChange={(e) => patchDraft({ phone: e.target.value })}
              placeholder="+201234567890"
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
            />
          </Field>
          <Field label="Currency">
            <select
              value={draft.currency ?? "EGP"}
              onChange={(e) => patchDraft({ currency: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
            >
              <option value="EGP">EGP</option>
              <option value="USD">USD</option>
              <option value="EUR">EUR</option>
              <option value="GBP">GBP</option>
              <option value="AED">AED</option>
              <option value="SAR">SAR</option>
            </select>
          </Field>
          <div className="md:col-span-2 flex flex-wrap gap-6">
            <label className="inline-flex items-center gap-2 text-sm text-slate-700">
              <input
                type="checkbox"
                checked={!!draft.accepts_marketing}
                onChange={(e) =>
                  patchDraft({ accepts_marketing: e.target.checked })
                }
                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
              />
              Subscribed to marketing emails
            </label>
            <label className="inline-flex items-center gap-2 text-sm text-slate-700">
              <input
                type="checkbox"
                checked={!!draft.tax_exempt}
                onChange={(e) => patchDraft({ tax_exempt: e.target.checked })}
                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
              />
              Tax exempt
            </label>
          </div>
        </Section>

        {/* Editable: Default address */}
        <Section title="Default address">
          <Field label="Address line 1" wide>
            <input
              type="text"
              value={draft.default_address?.address1 ?? ""}
              onChange={(e) => patchAddress({ address1: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Address line 2" wide>
            <input
              type="text"
              value={draft.default_address?.address2 ?? ""}
              onChange={(e) => patchAddress({ address2: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="City">
            <input
              type="text"
              value={draft.default_address?.city ?? ""}
              onChange={(e) => patchAddress({ city: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Province / State">
            <input
              type="text"
              value={draft.default_address?.province ?? ""}
              onChange={(e) => patchAddress({ province: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Country">
            <input
              type="text"
              value={draft.default_address?.country ?? ""}
              onChange={(e) => patchAddress({ country: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Zip / Postal code">
            <input
              type="text"
              value={draft.default_address?.zip ?? ""}
              onChange={(e) => patchAddress({ zip: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Company">
            <input
              type="text"
              value={draft.default_address?.company ?? ""}
              onChange={(e) => patchAddress({ company: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          <Field label="Phone">
            <input
              type="tel"
              value={draft.default_address?.phone ?? ""}
              onChange={(e) => patchAddress({ phone: e.target.value })}
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </Field>
          {isAddressEmpty(draft.default_address) && (
            <div className="md:col-span-2 text-xs text-slate-400 italic">
              No address on file. Fill in the fields above to add one.
            </div>
          )}
        </Section>

        {/* Editable: Tags */}
        <Section title="Tags" cols={1}>
          <div className="md:col-span-2">
            <div className="flex flex-wrap gap-1 mb-2">
              {(draft.tags ?? []).map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center gap-1 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                >
                  {t}
                  <button
                    type="button"
                    onClick={() =>
                      patchDraft({
                        tags: (draft.tags ?? []).filter((x) => x !== t),
                      })
                    }
                    className="text-slate-500 hover:text-rose-600"
                  >
                    ×
                  </button>
                </span>
              ))}
              {(!draft.tags || draft.tags.length === 0) && (
                <span className="text-xs text-slate-400">No tags yet</span>
              )}
            </div>
            <input
              type="text"
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === ",") {
                  e.preventDefault();
                  const t = tagInput.trim().replace(/,$/, "");
                  if (t && !(draft.tags ?? []).includes(t)) {
                    patchDraft({ tags: [...(draft.tags ?? []), t] });
                  }
                  setTagInput("");
                }
              }}
              placeholder="Type a tag and press Enter"
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm"
            />
          </div>
        </Section>

        {/* Editable: Note */}
        <Section title="Note" cols={1}>
          <div className="md:col-span-2">
            <textarea
              rows={4}
              value={draft.note ?? ""}
              onChange={(e) => patchDraft({ note: e.target.value })}
              placeholder="Internal note about this customer (not visible to customer)"
              className="w-full border border-slate-300 rounded-md px-3 py-2 text-sm resize-y"
            />
          </div>
        </Section>

        {/* All addresses (read-only listing of additional non-default addresses) */}
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
            <div className="overflow-x-auto">
              <table className="min-w-[680px] text-sm">
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
            </div>
          ) : (
            <div className="px-4 py-6 text-center text-sm text-slate-400">
              No orders yet
            </div>
          )}
        </div>
      </div>
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

function Section({
  title,
  children,
  cols = 2,
}: {
  title: string;
  children: React.ReactNode;
  cols?: 1 | 2;
}) {
  return (
    <div className="bg-white border border-slate-200 rounded-xl p-5">
      <div className="text-sm font-semibold text-slate-900 mb-4">{title}</div>
      <div
        className={`grid grid-cols-1 ${cols === 2 ? "md:grid-cols-2" : ""} gap-4`}
      >
        {children}
      </div>
    </div>
  );
}

function Field({
  label,
  children,
  wide,
}: {
  label: string;
  children: React.ReactNode;
  wide?: boolean;
}) {
  return (
    <div className={wide ? "md:col-span-2" : ""}>
      <label className="block text-xs font-medium text-slate-600 mb-1">
        {label}
      </label>
      {children}
    </div>
  );
}
