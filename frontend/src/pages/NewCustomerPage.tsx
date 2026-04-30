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
  const [currency, setCurrency] = useState("USD");
  const [tagsInput, setTagsInput] = useState("");
  const [address1, setAddress1] = useState("");
  const [address2, setAddress2] = useState("");
  const [city, setCity] = useState("");
  const [province, setProvince] = useState("");
  const [country, setCountry] = useState("");
  const [zip, setZip] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const tags = tagsInput
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean);

      const default_address: Record<string, string | undefined> = {};
      if (address1) default_address.address1 = address1;
      if (address2) default_address.address2 = address2;
      if (city) default_address.city = city;
      if (province) default_address.province = province;
      if (country) default_address.country = country;
      if (zip) default_address.zip = zip;

      const created = await customersApi.create({
        first_name: firstName || undefined,
        last_name: lastName || undefined,
        email: email || undefined,
        phone: phone || undefined,
        currency: currency || undefined,
        tags,
        default_address:
          Object.keys(default_address).length > 0 ? default_address : undefined,
      });
      navigate(`/customers?highlight=${created.id}`);
    } catch (err: any) {
      const msg =
        err?.response?.data?.error?.detail ||
        err?.message ||
        "Failed to create customer";
      setError(msg);
    } finally {
      setSaving(false);
    }
  }

  const input =
    "w-full border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none";
  const label = "block text-xs font-medium text-slate-600 mb-1";

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
          <h2 className="text-sm font-semibold text-slate-800 mb-3">Contact</h2>
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
              <label className={label}>Email</label>
              <input
                type="email"
                className={input}
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div>
              <label className={label}>Phone</label>
              <input
                className={input}
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
            </div>
            <div>
              <label className={label}>Currency</label>
              <input
                className={input}
                value={currency}
                onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                maxLength={3}
              />
            </div>
            <div>
              <label className={label}>Tags (comma-separated)</label>
              <input
                className={input}
                value={tagsInput}
                onChange={(e) => setTagsInput(e.target.value)}
                placeholder="vip, wholesale"
              />
            </div>
          </div>
        </section>

        <section>
          <h2 className="text-sm font-semibold text-slate-800 mb-3">
            Default address
          </h2>
          <div className="grid grid-cols-2 gap-4">
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
