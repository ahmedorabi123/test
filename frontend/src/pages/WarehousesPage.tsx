import { useEffect, useState, useCallback } from "react";
import { warehousesApi, type Warehouse } from "../api/inventory";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { Modal } from "../components/ui/Modal";
import { PageContainer } from "../components/ui/PageContainer";

const KIND_LABELS: Record<string, string> = {
  own: "Own",
  consignment: "Showroom (consignment)",
  transit: "Transit",
};

const KIND_BADGES: Record<string, string> = {
  own: "bg-slate-100 text-slate-700",
  consignment: "bg-emerald-100 text-emerald-700",
  transit: "bg-amber-100 text-amber-700",
};

export default function WarehousesPage() {
  const [items, setItems] = useState<Warehouse[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Warehouse | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    warehousesApi
      .list()
      .then(setItems)
      .catch((e) => setError((e as Error).message || "Failed to load"))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const grouped = {
    own: items.filter((w) => (w.kind || "own") === "own"),
    consignment: items.filter((w) => w.kind === "consignment"),
    transit: items.filter((w) => w.kind === "transit"),
  };

  return (
    <PageContainer className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Warehouses</h1>
          <p className="text-sm text-slate-500 mt-1">
            {items.length} warehouse{items.length === 1 ? "" : "s"} ·{" "}
            {grouped.consignment.length} showroom
            {grouped.consignment.length === 1 ? "" : "s"}
          </p>
        </div>
        <button
          onClick={() => setCreating(true)}
          className="inline-flex min-h-11 items-center justify-center rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + New warehouse
        </button>
      </div>

      {error && (
        <div className="bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      {(["own", "consignment", "transit"] as const).map((kind) => (
        <Section
          key={kind}
          title={KIND_LABELS[kind]}
          warehouses={grouped[kind]}
          loading={loading}
          onEdit={setEditing}
        />
      ))}

      {(creating || editing) && (
        <WarehouseModal
          initial={editing}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
          onSaved={() => {
            setCreating(false);
            setEditing(null);
            load();
          }}
        />
      )}
    </PageContainer>
  );
}

function Section({
  title,
  warehouses,
  loading,
  onEdit,
}: {
  title: string;
  warehouses: Warehouse[];
  loading: boolean;
  onEdit: (w: Warehouse) => void;
}) {
  if (warehouses.length === 0 && !loading) return null;
  return (
    <div className="bg-white border border-slate-200 rounded-xl shadow-sm overflow-hidden">
      <div className="px-4 py-3 border-b border-slate-200 bg-slate-50">
        <h2 className="text-sm font-semibold text-slate-700">
          {title}{" "}
          <span className="text-slate-400 font-normal">
            ({warehouses.length})
          </span>
        </h2>
      </div>
      <div className="space-y-3 p-3 md:hidden">
        {warehouses.map((w) => (
          <MobileRowCard
            key={w.id}
            title={w.name}
            subtitle={
              w.partner_name ||
              w.partner_email ||
              w.partner_phone ||
              "No partner contact"
            }
            meta={w.currency || "-"}
            fields={[
              {
                label: "Code",
                value: (
                  <span
                    className={`inline-block rounded px-2 py-0.5 text-xs ${KIND_BADGES[w.kind || "own"]}`}
                  >
                    {w.code}
                  </span>
                ),
              },
              {
                label: "Commission",
                value: w.commission_rate
                  ? `${(Number(w.commission_rate) * 100).toFixed(2)}%`
                  : "-",
              },
              {
                label: "Status",
                value: w.active ? "Active" : "Inactive",
              },
            ]}
            actions={
              <button
                onClick={() => onEdit(w)}
                className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
              >
                Edit warehouse
              </button>
            }
          />
        ))}
      </div>
      <div className="hidden overflow-x-auto md:block">
        <table className="min-w-full divide-y divide-slate-200">
          <thead className="bg-white text-xs text-slate-500 uppercase">
            <tr>
              <th className="px-4 py-2 text-left">Name</th>
              <th className="px-4 py-2 text-left">Code</th>
              <th className="px-4 py-2 text-left">Partner / Contact</th>
              <th className="px-4 py-2 text-right">Commission</th>
              <th className="px-4 py-2 text-left">Currency</th>
              <th className="px-4 py-2 text-left">Status</th>
              <th className="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 text-sm">
            {warehouses.map((w) => (
              <tr key={w.id} className="hover:bg-slate-50">
                <td className="px-4 py-2 font-medium text-slate-800">
                  {w.name}
                </td>
                <td className="px-4 py-2 text-slate-600">
                  <span
                    className={`inline-block text-xs px-2 py-0.5 rounded ${
                      KIND_BADGES[w.kind || "own"]
                    } mr-2`}
                  >
                    {w.code}
                  </span>
                  {w.shopify_location_id && (
                    <span className="text-xs text-slate-400">
                      Shopify #{w.shopify_location_id}
                    </span>
                  )}
                </td>
                <td className="px-4 py-2 text-slate-600">
                  {w.partner_name && <div>{w.partner_name}</div>}
                  {w.partner_email && (
                    <div className="text-xs text-slate-500">
                      {w.partner_email}
                    </div>
                  )}
                  {w.partner_phone && (
                    <div className="text-xs text-slate-500">
                      {w.partner_phone}
                    </div>
                  )}
                  {!w.partner_name && !w.partner_email && !w.partner_phone && (
                    <span className="text-slate-300">—</span>
                  )}
                </td>
                <td className="px-4 py-2 text-right text-slate-600">
                  {w.commission_rate
                    ? `${(Number(w.commission_rate) * 100).toFixed(2)}%`
                    : "—"}
                </td>
                <td className="px-4 py-2 text-slate-600">
                  {w.currency || "—"}
                </td>
                <td className="px-4 py-2">
                  <span
                    className={
                      w.active
                        ? "text-xs bg-emerald-100 text-emerald-700 px-2 py-0.5 rounded"
                        : "text-xs bg-slate-100 text-slate-500 px-2 py-0.5 rounded"
                    }
                  >
                    {w.active ? "Active" : "Inactive"}
                  </span>
                </td>
                <td className="px-4 py-2 text-right">
                  <button
                    onClick={() => onEdit(w)}
                    className="text-indigo-600 hover:text-indigo-800 text-sm font-medium"
                  >
                    Edit
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function WarehouseModal({
  initial,
  onClose,
  onSaved,
}: {
  initial: Warehouse | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    name: initial?.name || "",
    code: initial?.code || "",
    kind: (initial?.kind || "own") as "own" | "consignment" | "transit",
    address: initial?.address || "",
    partner_name: initial?.partner_name || "",
    partner_email: initial?.partner_email || "",
    partner_phone: initial?.partner_phone || "",
    commission_rate:
      initial?.commission_rate != null ? String(initial.commission_rate) : "",
    currency: initial?.currency || "EGP",
    notes: initial?.notes || "",
    active: initial?.active ?? true,
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const update = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) =>
    setForm((f) => ({ ...f, [k]: v }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSaving(true);
    const payload: Partial<Warehouse> = {
      name: form.name,
      code: form.code.toUpperCase(),
      kind: form.kind,
      address: form.address || null,
      partner_name: form.partner_name || null,
      partner_email: form.partner_email || null,
      partner_phone: form.partner_phone || null,
      commission_rate: form.commission_rate ? form.commission_rate : null,
      currency: form.currency || null,
      notes: form.notes || null,
      active: form.active,
    };
    try {
      if (initial) {
        await warehousesApi.update(initial.id, payload);
      } else {
        await warehousesApi.create(payload);
      }
      onSaved();
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string; errors?: string[] } } })
          ?.response?.data?.error ||
        (
          e as { response?: { data?: { errors?: string[] } } }
        )?.response?.data?.errors?.join(", ") ||
        (e as Error).message;
      setError(msg);
    } finally {
      setSaving(false);
    }
  };

  const isShowroom = form.kind === "consignment";

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={initial ? "Edit warehouse" : "New warehouse"}
    >
      <form onSubmit={submit} className="space-y-3">
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Name *</span>
            <input
              required
              value={form.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="e.g. Cairo Showroom"
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Code *</span>
            <input
              required
              value={form.code}
              onChange={(e) => update("code", e.target.value.toUpperCase())}
              placeholder="CAIRO-SR"
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2 uppercase"
            />
          </label>
        </div>

        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Kind *</span>
            <select
              value={form.kind}
              onChange={(e) =>
                update(
                  "kind",
                  e.target.value as "own" | "consignment" | "transit",
                )
              }
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
            >
              <option value="own">Own warehouse</option>
              <option value="consignment">Showroom (consignment)</option>
              <option value="transit">Transit</option>
            </select>
          </label>
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Currency</span>
            <input
              value={form.currency}
              onChange={(e) => update("currency", e.target.value.toUpperCase())}
              maxLength={3}
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2 uppercase"
            />
          </label>
        </div>

        <label className="block text-sm">
          <span className="block text-slate-600 mb-1">Address</span>
          <input
            value={form.address}
            onChange={(e) => update("address", e.target.value)}
            className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
          />
        </label>

        {isShowroom && (
          <fieldset className="border border-emerald-200 bg-emerald-50/40 rounded p-3 space-y-3">
            <legend className="text-xs font-semibold text-emerald-700 px-1">
              Showroom partner details
            </legend>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">
                  Partner / Owner name
                </span>
                <input
                  value={form.partner_name}
                  onChange={(e) => update("partner_name", e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">
                  Commission rate
                </span>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    step="0.0001"
                    min={0}
                    max={1}
                    value={form.commission_rate}
                    onChange={(e) => update("commission_rate", e.target.value)}
                    placeholder="0.15"
                    className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                  />
                  <span className="text-xs text-slate-500 whitespace-nowrap">
                    = {(Number(form.commission_rate || 0) * 100).toFixed(2)}%
                  </span>
                </div>
              </label>
            </div>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">Partner email</span>
                <input
                  type="email"
                  value={form.partner_email}
                  onChange={(e) => update("partner_email", e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="text-sm">
                <span className="block text-slate-600 mb-1">Partner phone</span>
                <input
                  value={form.partner_phone}
                  onChange={(e) => update("partner_phone", e.target.value)}
                  className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                />
              </label>
            </div>
          </fieldset>
        )}

        <label className="block text-sm">
          <span className="block text-slate-600 mb-1">Notes</span>
          <textarea
            value={form.notes}
            onChange={(e) => update("notes", e.target.value)}
            rows={2}
            className="w-full rounded border border-slate-300 px-3 py-2"
          />
        </label>

        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            checked={form.active}
            onChange={(e) => update("active", e.target.checked)}
          />
          Active
        </label>

        {error && (
          <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
            {error}
          </div>
        )}

        <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 rounded border border-slate-300 px-3 text-sm"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saving}
            className="min-h-11 rounded bg-indigo-600 px-4 text-sm font-medium text-white hover:bg-indigo-700 disabled:bg-slate-400"
          >
            {saving ? "Saving…" : initial ? "Save changes" : "Create"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
