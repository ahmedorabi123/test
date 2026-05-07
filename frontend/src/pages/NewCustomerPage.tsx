import { useState, FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { customersApi } from "../api/customers";

export default function NewCustomerPage() {
  const navigate = useNavigate();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [currency, setCurrency] = useState("EGP");
  const [tags, setTags] = useState<string[]>([]);
  const [tagInput, setTagInput] = useState("");
  const [acceptsMarketing, setAcceptsMarketing] = useState(false);
  const [taxExempt, setTaxExempt] = useState(false);
  const [note, setNote] = useState("");
  const [company, setCompany] = useState("");
  const [addressPhone, setAddressPhone] = useState("");
  const [address1, setAddress1] = useState("");
  const [address2, setAddress2] = useState("");
  const [city, setCity] = useState("");
  const [province, setProvince] = useState("");
  const [country, setCountry] = useState("");
  const [zip, setZip] = useState("");

  function addTag() {
    const t = tagInput.trim().replace(/,$/, "");
    if (t && !tags.includes(t)) setTags([...tags, t]);
    setTagInput("");
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();

    if (!email.trim() && !phone.trim()) {
      setError("Either an email or a phone number is required.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const default_address: Record<string, string> = {};
      if (address1) default_address.address1 = address1;
      if (address2) default_address.address2 = address2;
      if (city) default_address.city = city;
      if (province) default_address.province = province;
      if (country) default_address.country = country;
      if (zip) default_address.zip = zip;
      if (company) default_address.company = company;
      if (addressPhone) default_address.phone = addressPhone;

      const created = await customersApi.create({
        first_name: firstName || undefined,
        last_name: lastName || undefined,
        email: email || undefined,
        phone: phone || undefined,
        currency: currency || undefined,
        tags,
        accepts_marketing: acceptsMarketing,
        tax_exempt: taxExempt,
        note: note || undefined,
        default_address:
          Object.keys(default_address).length > 0 ? default_address : undefined,
      });
      navigate(`/customers/${created.id}`);
    } catch (err: unknown) {
      const e = err as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        e?.response?.data?.error?.detail ||
          e?.message ||
          "Failed to create customer",
      );
    } finally {
      setSaving(false);
    }
  }

  const input =
    "w-full border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none";
  const label = "block text-xs font-medium text-slate-600 mb-1";
  const required = <span className="text-rose-500">*</span>;

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-semibold text-slate-900 mb-6">
        New customer
      </h1>

      {error && (
        <div className="mb-4 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <form
        onSubmit={handleSubmit}
        className="space-y-6 bg-white border border-slate-200 rounded-xl p-6 shadow-sm"
      >
        <section>
          <h2 className="text-sm font-semibold text-slate-800 mb-3">
            Customer overview
          </h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={label}>First name</label>
              <input
                className={input}
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Last name</label>
              <input
                className={input}
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Email {required}</label>
              <input
                type="email"
                className={input}
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="customer@example.com"
              />
            </div>
            <div>
              <label className={label}>Phone {required}</label>
              <input
                className={input}
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+201234567890"
              />
            </div>
            <div className="col-span-2 -mt-1 text-xs text-slate-500">
              Either email or phone is required (matches Shopify).
            </div>
            <div>
              <label className={label}>Currency {required}</label>
              <select
                className={input}
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
              >
                <option value="EGP">EGP</option>
                <option value="USD">USD</option>
                <option value="EUR">EUR</option>
                <option value="GBP">GBP</option>
                <option value="AED">AED</option>
                <option value="SAR">SAR</option>
              </select>
            </div>
            <div className="flex items-end gap-6">
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input
                  type="checkbox"
                  checked={acceptsMarketing}
                  onChange={(e) => setAcceptsMarketing(e.target.checked)}
                  className="rounded border-slate-300 text-indigo-600"
                />
                Subscribed to marketing
              </label>
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input
                  type="checkbox"
                  checked={taxExempt}
                  onChange={(e) => setTaxExempt(e.target.checked)}
                  className="rounded border-slate-300 text-indigo-600"
                />
                Tax exempt
              </label>
            </div>
          </div>
        </section>

        <section>
          <h2 className="text-sm font-semibold text-slate-800 mb-3">
            Default address
          </h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={label}>Company</label>
              <input
                className={input}
                value={company}
                onChange={(e) => setCompany(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Phone</label>
              <input
                className={input}
                value={addressPhone}
                onChange={(e) => setAddressPhone(e.target.value)}
              />
            </div>
            <div className="col-span-2">
              <label className={label}>Address line 1</label>
              <input
                className={input}
                value={address1}
                onChange={(e) => setAddress1(e.target.value)}
              />
            </div>
            <div className="col-span-2">
              <label className={label}>Address line 2</label>
              <input
                className={input}
                value={address2}
                onChange={(e) => setAddress2(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>City</label>
              <input
                className={input}
                value={city}
                onChange={(e) => setCity(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Province / State</label>
              <input
                className={input}
                value={province}
                onChange={(e) => setProvince(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Country</label>
              <input
                className={input}
                value={country}
                onChange={(e) => setCountry(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>ZIP / Postal code</label>
              <input
                className={input}
                value={zip}
                onChange={(e) => setZip(e.target.value)}
              />
            </div>
          </div>
        </section>

        <section>
          <h2 className="text-sm font-semibold text-slate-800 mb-3">Tags</h2>
          <div className="flex flex-wrap gap-1 mb-2">
            {tags.map((t) => (
              <span
                key={t}
                className="inline-flex items-center gap-1 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
              >
                {t}
                <button
                  type="button"
                  onClick={() => setTags(tags.filter((x) => x !== t))}
                  className="text-slate-500 hover:text-rose-600"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
          <input
            className={input}
            value={tagInput}
            onChange={(e) => setTagInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === ",") {
                e.preventDefault();
                addTag();
              }
            }}
            onBlur={addTag}
            placeholder="vip, wholesale (Enter to add)"
          />
        </section>

        <section>
          <h2 className="text-sm font-semibold text-slate-800 mb-3">Note</h2>
          <textarea
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            className={input + " resize-y"}
            placeholder="Internal note (only visible to staff)"
          />
        </section>

        <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-200">
          <button
            type="button"
            className="text-sm text-slate-600 hover:text-slate-900 px-3 py-2"
            onClick={() => navigate("/customers")}
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saving}
            className="inline-flex items-center bg-indigo-600 text-white text-sm font-medium px-4 py-2 rounded-lg hover:bg-indigo-700 disabled:opacity-50"
          >
            {saving ? "Saving…" : "Create customer"}
          </button>
        </div>
      </form>
    </div>
  );
}
