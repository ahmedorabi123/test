import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { suppliersApi } from "../api/suppliers";

export default function NewSupplierPage() {
  const navigate = useNavigate();
  const [form, setForm] = useState({
    supplier_code: "",
    name: "",
    email: "",
    phone: "",
    currency: "EGP",
    status: "active",
    lead_time_days: "",
    tax_id: "",
    address_line1: "",
    address_line2: "",
    city: "",
    governorate: "",
    country: "EG",
    payment_net_days: "30",
    payment_notes: "",
    notes: "",
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (k: keyof typeof form, v: string) =>
    setForm((prev) => ({ ...prev, [k]: v }));

  async function save() {
    if (!form.name.trim()) {
      setError("Name is required");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const created = await suppliersApi.create({
        supplier_code: form.supplier_code.trim() || undefined,
        name: form.name.trim(),
        email: form.email || null,
        phone: form.phone || null,
        currency: form.currency || "EGP",
        status: form.status as "active" | "on_hold" | "inactive",
        lead_time_days: form.lead_time_days
          ? Number(form.lead_time_days)
          : undefined,
        tax_id: form.tax_id || null,
        address: {
          line1: form.address_line1 || null,
          line2: form.address_line2 || null,
          city: form.city || null,
          governorate: form.governorate || null,
          country: form.country || null,
        },
        payment_terms: {
          net_days: Number(form.payment_net_days || 0),
          notes: form.payment_notes || null,
        },
        notes: form.notes || null,
      });
      navigate(`/suppliers/${created.id}`);
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        err.response?.data?.error?.detail || err.message || "Failed to create",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 p-4 sm:p-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">New supplier</h1>
      </div>

      {error && (
        <div className="bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <div className="space-y-4 rounded-xl border border-slate-200 bg-white p-4 sm:p-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Name *
            </label>
            <input
              type="text"
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Supplier code
            </label>
            <input
              type="text"
              value={form.supplier_code}
              onChange={(e) => set("supplier_code", e.target.value.toUpperCase())}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm font-mono"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Email
            </label>
            <input
              type="email"
              value={form.email}
              onChange={(e) => set("email", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Phone
            </label>
            <input
              type="text"
              value={form.phone}
              onChange={(e) => set("phone", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Currency
            </label>
            <input
              type="text"
              value={form.currency}
              onChange={(e) => set("currency", e.target.value.toUpperCase())}
              maxLength={3}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm font-mono"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Status
            </label>
            <select
              value={form.status}
              onChange={(e) => set("status", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            >
              <option value="active">Active</option>
              <option value="on_hold">On hold</option>
              <option value="inactive">Inactive</option>
            </select>
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Lead time days
            </label>
            <input
              type="number"
              min={0}
              value={form.lead_time_days}
              onChange={(e) => set("lead_time_days", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Tax ID
            </label>
            <input
              type="text"
              value={form.tax_id}
              onChange={(e) => set("tax_id", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Address line 1
            </label>
            <input
              type="text"
              value={form.address_line1}
              onChange={(e) => set("address_line1", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Address line 2
            </label>
            <input
              type="text"
              value={form.address_line2}
              onChange={(e) => set("address_line2", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              City
            </label>
            <input
              type="text"
              value={form.city}
              onChange={(e) => set("city", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Governorate
            </label>
            <input
              type="text"
              value={form.governorate}
              onChange={(e) => set("governorate", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Country
            </label>
            <input
              type="text"
              value={form.country}
              onChange={(e) => set("country", e.target.value.toUpperCase())}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Payment net days
            </label>
            <select
              value={form.payment_net_days}
              onChange={(e) => set("payment_net_days", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            >
              <option value="0">Due on receipt</option>
              <option value="7">Net 7</option>
              <option value="15">Net 15</option>
              <option value="30">Net 30</option>
              <option value="45">Net 45</option>
              <option value="60">Net 60</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Payment notes
            </label>
            <input
              type="text"
              value={form.payment_notes}
              onChange={(e) => set("payment_notes", e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Notes
          </label>
          <textarea
            rows={3}
            value={form.notes}
            onChange={(e) => set("notes", e.target.value)}
            className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
          />
        </div>
      </div>

      <div className="flex items-center justify-end gap-2">
        <button
          type="button"
          onClick={() => navigate("/suppliers")}
          className="text-sm text-slate-600 hover:text-slate-900 px-3 py-2"
        >
          Cancel
        </button>
        <button
          type="button"
          disabled={saving}
          onClick={save}
          className="bg-indigo-600 text-white text-sm font-medium px-4 py-2 rounded-lg hover:bg-indigo-700 disabled:opacity-50"
        >
          {saving ? "Saving…" : "Create supplier"}
        </button>
      </div>
    </div>
  );
}
