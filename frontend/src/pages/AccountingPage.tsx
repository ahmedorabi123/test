import React, { useEffect, useState, useCallback, useMemo } from "react";
import {
  accountingApi,
  type Account,
  type JournalEntry,
  type TrialBalance,
  type Pnl,
  type BalanceSheet,
  type AccountLedgerRow,
} from "../api/accounting";
import { suppliersApi, type Supplier } from "../api/suppliers";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";
import { Tabs } from "../components/ui/Tabs";

// ── helpers ───────────────────────────────────────────────────────────────────

type SortDir = "asc" | "desc";

function nextDir(current: SortDir | null): SortDir {
  return current === "asc" ? "desc" : "asc";
}

function SortHeader({
  label,
  active,
  dir,
  onClick,
  align = "left",
}: {
  label: string;
  active: boolean;
  dir: SortDir;
  onClick: () => void;
  align?: "left" | "right";
}) {
  return (
    <th
      onClick={onClick}
      className={`px-4 py-2 cursor-pointer select-none hover:bg-slate-100 ${align === "right" ? "text-right" : "text-left"}`}
    >
      <span className="inline-flex items-center gap-1">
        {label}
        <span
          className={`text-xs ${active ? "text-indigo-600" : "text-slate-300"}`}
        >
          {active ? (dir === "asc" ? "▲" : "▼") : "↕"}
        </span>
      </span>
    </th>
  );
}

function fmt(n: number) {
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function dateInput(d: Date) {
  return d.toISOString().slice(0, 10);
}

// ── sub-components ────────────────────────────────────────────────────────────

function Badge({ v }: { v: string }) {
  const map: Record<string, string> = {
    posted: "bg-emerald-100 text-emerald-700",
    reversed: "bg-rose-100 text-rose-700",
    draft: "bg-amber-100 text-amber-700",
    sale: "bg-indigo-100 text-indigo-700",
    refund: "bg-rose-100 text-rose-700",
    asset: "bg-sky-100 text-sky-700",
    liability: "bg-orange-100 text-orange-700",
    equity: "bg-violet-100 text-violet-700",
    revenue: "bg-emerald-100 text-emerald-700",
    expense: "bg-red-100 text-red-700",
  };
  return (
    <span
      className={`inline-block rounded px-2 py-0.5 text-xs font-medium ${map[v] ?? "bg-slate-100 text-slate-600"}`}
    >
      {v}
    </span>
  );
}

// ── Account Form Modal ────────────────────────────────────────────────────────

const ACCOUNT_TYPES = ["asset", "liability", "equity", "revenue", "expense"] as const;
const NORMAL_SIDES  = ["debit", "credit"] as const;

const defaultSideForType: Record<string, "debit" | "credit"> = {
  asset:     "debit",
  expense:   "debit",
  liability: "credit",
  equity:    "credit",
  revenue:   "credit",
};

interface AccountFormState {
  code: string;
  name: string;
  account_type: string;
  normal_side: string;
  currency: string;
  description: string;
  active: boolean;
}

function AccountFormModal({
  initial,
  onClose,
  onSaved,
}: {
  initial: Account | null;
  onClose: () => void;
  onSaved: (a: Account) => void;
}) {
  const isEdit = initial != null;
  const [form, setForm] = useState<AccountFormState>({
    code:         initial?.code         ?? "",
    name:         initial?.name         ?? "",
    account_type: initial?.account_type ?? "expense",
    normal_side:  initial?.normal_side  ?? "debit",
    currency:     initial?.currency     ?? "EGP",
    description:  initial?.description  ?? "",
    active:       initial?.active       ?? true,
  });
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState("");

  const set = (k: keyof AccountFormState, v: string | boolean) =>
    setForm((f) => ({ ...f, [k]: v }));

  const handleTypeChange = (t: string) => {
    setForm((f) => ({
      ...f,
      account_type: t,
      normal_side: defaultSideForType[t] ?? "debit",
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setSaving(true);
    try {
      let result: { data: Account };
      if (isEdit) {
        result = await accountingApi.updateAccount(initial!.id, {
          code:         form.code,
          name:         form.name,
          account_type: form.account_type,
          normal_side:  form.normal_side,
          currency:     form.currency,
          description:  form.description,
          active:       form.active,
        });
      } else {
        result = await accountingApi.createAccount({
          code:         form.code,
          name:         form.name,
          account_type: form.account_type,
          normal_side:  form.normal_side,
          currency:     form.currency,
          description:  form.description,
        });
      }
      onSaved(result.data);
    } catch (err: unknown) {
      const msg =
        (err as { response?: { data?: { error?: { detail?: string } } } })
          ?.response?.data?.error?.detail ?? "Save failed";
      setError(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-lg rounded-xl bg-white shadow-xl">
        <div className="flex items-center justify-between border-b px-5 py-4">
          <h2 className="font-semibold text-slate-800">
            {isEdit ? "Edit Account" : "New Account"}
          </h2>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-600 text-xl leading-none"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {error && (
            <p className="rounded bg-red-50 px-3 py-2 text-sm text-red-600">
              {error}
            </p>
          )}

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Account Code *
              </label>
              <input
                required
                value={form.code}
                onChange={(e) => set("code", e.target.value.trim())}
                placeholder="e.g. 6100"
                className="w-full rounded-md border px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-400"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Currency
              </label>
              <input
                value={form.currency}
                onChange={(e) => set("currency", e.target.value.toUpperCase())}
                maxLength={3}
                className="w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Account Name *
            </label>
            <input
              required
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              placeholder="e.g. Rent &amp; Occupancy"
              className="w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Account Type *
              </label>
              <select
                required
                value={form.account_type}
                onChange={(e) => handleTypeChange(e.target.value)}
                className="w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
              >
                {ACCOUNT_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {t.charAt(0).toUpperCase() + t.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Normal Side *
              </label>
              <select
                required
                value={form.normal_side}
                onChange={(e) => set("normal_side", e.target.value)}
                className="w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
              >
                {NORMAL_SIDES.map((s) => (
                  <option key={s} value={s}>
                    {s.charAt(0).toUpperCase() + s.slice(1)}
                  </option>
                ))}
              </select>
              <p className="text-xs text-slate-400 mt-1">
                Assets &amp; expenses = Debit; Liabilities, equity &amp; revenue = Credit
              </p>
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Description
            </label>
            <input
              value={form.description}
              onChange={(e) => set("description", e.target.value)}
              placeholder="Optional — brief description"
              className="w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
            />
          </div>

          {isEdit && (
            <div className="flex items-center gap-3">
              <input
                id="acc-active"
                type="checkbox"
                checked={form.active}
                onChange={(e) => set("active", e.target.checked)}
                className="h-4 w-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-400"
              />
              <label htmlFor="acc-active" className="text-sm text-slate-700">
                Active (uncheck to deactivate)
              </label>
            </div>
          )}

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border px-4 py-2 text-sm text-slate-600 hover:bg-slate-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving}
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {saving ? "Saving…" : isEdit ? "Save changes" : "Create account"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Accounts tab ─────────────────────────────────────────────────────────────

function AccountsTab() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [sortKey, setSortKey] = useState<"code" | "name">("code");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [formTarget, setFormTarget] = useState<Account | null | "new">(null);

  const loadAccounts = useCallback(() => {
    setLoading(true);
    accountingApi
      .accounts()
      .then((r) => setAccounts(r.data))
      .catch(() => setError("Failed to load chart of accounts"))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { loadAccounts(); }, [loadAccounts]);

  const onSort = (key: "code" | "name") => {
    if (sortKey === key) setSortDir(nextDir(sortDir));
    else { setSortKey(key); setSortDir("asc"); }
  };

  const sortRows = (rows: Account[]) => {
    const sorted = [...rows].sort((a, b) => {
      const av = a[sortKey] ?? "";
      const bv = b[sortKey] ?? "";
      return av.localeCompare(bv);
    });
    return sortDir === "asc" ? sorted : sorted.reverse();
  };

  const handleSaved = (saved: Account) => {
    setAccounts((prev) => {
      const idx = prev.findIndex((a) => a.id === saved.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = saved;
        return next;
      }
      return [...prev, saved];
    });
    setFormTarget(null);
  };

  if (loading) return <p className="text-slate-500 p-6">Loading…</p>;
  if (error)   return <p className="text-red-500 p-6">{error}</p>;

  const groups = ["asset", "liability", "equity", "revenue", "expense"] as const;

  return (
    <>
      {formTarget != null && (
        <AccountFormModal
          initial={formTarget === "new" ? null : formTarget}
          onClose={() => setFormTarget(null)}
          onSaved={handleSaved}
        />
      )}

      <div className="space-y-6">
        <div className="flex justify-end">
          <button
            onClick={() => setFormTarget("new")}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700"
          >
            + New Account
          </button>
        </div>

        {groups.map((g) => {
          const rows = sortRows(accounts.filter((a) => a.account_type === g));
          if (!rows.length) return null;
          return (
            <div key={g}>
              <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2 px-1">
                {g}s
              </h3>
              {/* Mobile cards */}
              <div className="space-y-2 md:hidden">
                {rows.map((a) => (
                  <MobileRowCard
                    key={a.id}
                    title={
                      <span className="font-mono text-sm text-slate-900">
                        {a.code}
                      </span>
                    }
                    subtitle={a.name}
                    fields={[
                      { label: "Normal side", value: <Badge v={a.normal_side} /> },
                      { label: "Currency", value: a.currency },
                      {
                        label: "Status",
                        value: a.active ? (
                          <span className="text-emerald-600 text-xs">Active</span>
                        ) : (
                          <span className="text-slate-400 text-xs">Inactive</span>
                        ),
                      },
                    ]}
                    actions={
                      <button
                        type="button"
                        onClick={() => setFormTarget(a)}
                        className="inline-flex min-h-9 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-xs font-medium text-slate-700 hover:bg-slate-50"
                      >
                        Edit
                      </button>
                    }
                  />
                ))}
              </div>
              {/* Desktop table */}
              <div className="hidden md:block overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
                <table className="min-w-full text-sm">
                  <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
                    <tr>
                      <SortHeader label="Code" active={sortKey === "code"} dir={sortDir} onClick={() => onSort("code")} />
                      <SortHeader label="Name" active={sortKey === "name"} dir={sortDir} onClick={() => onSort("name")} />
                      <th className="px-4 py-2 text-left">Normal Side</th>
                      <th className="px-4 py-2 text-left">Currency</th>
                      <th className="px-4 py-2 text-left">Status</th>
                      <th className="px-4 py-2 text-left">Description</th>
                      <th className="px-4 py-2"></th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {rows.map((a) => (
                      <tr key={a.id} className="hover:bg-slate-50">
                        <td className="px-4 py-2 font-mono font-medium text-slate-700">{a.code}</td>
                        <td className="px-4 py-2 text-slate-800">{a.name}</td>
                        <td className="px-4 py-2"><Badge v={a.normal_side} /></td>
                        <td className="px-4 py-2 text-slate-500">{a.currency}</td>
                        <td className="px-4 py-2">
                          <span className={`text-xs font-medium ${a.active ? "text-emerald-600" : "text-slate-400"}`}>
                            {a.active ? "Active" : "Inactive"}
                          </span>
                        </td>
                        <td className="px-4 py-2 text-slate-400 text-xs max-w-xs truncate">
                          {a.description ?? ""}
                        </td>
                        <td className="px-4 py-2">
                          <button
                            onClick={() => setFormTarget(a)}
                            className="text-xs text-indigo-600 hover:underline"
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
        })}
      </div>
    </>
  );
}

// ── Journal tab ───────────────────────────────────────────────────────────────

function JournalTab() {
  const today = new Date();
  const [from, setFrom] = useState(
    dateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
  );
  const [to, setTo] = useState(dateInput(today));
  const [q, setQ] = useState("");
  const [minAmount, setMinAmount] = useState("");
  const [maxAmount, setMaxAmount] = useState("");
  const [accountCode, setAccountCode] = useState("");
  const [entries, setEntries] = useState<JournalEntry[]>([]);
  const [meta, setMeta] = useState({ page: 1, per_page: 25, total: 0 });
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState<number>(25);
  const [sortKey, setSortKey] = useState<string>("entry_date");
  const [sortDir, setSortDir] = useState<SortDir>("desc");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);
  const [expandedEntry, setExpandedEntry] = useState<JournalEntry | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    accountingApi
      .journalEntries({
        from,
        to,
        q: q || undefined,
        min_amount: minAmount || undefined,
        max_amount: maxAmount || undefined,
        account_code: accountCode || undefined,
        page,
        per_page: perPage,
        sort: sortKey,
        dir: sortDir,
      })
      .then((r) => {
        setEntries(r.data);
        setMeta(r.meta);
      })
      .catch(() => setError("Failed to load journal entries"))
      .finally(() => setLoading(false));
  }, [from, to, q, minAmount, maxAmount, accountCode, page, perPage, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const toggleSort = (key: string) => {
    if (sortKey === key) setSortDir(nextDir(sortDir));
    else {
      setSortKey(key);
      setSortDir("asc");
    }
    setPage(1);
  };

  const toggleExpand = async (id: string) => {
    if (expanded === id) {
      setExpanded(null);
      setExpandedEntry(null);
      return;
    }
    setExpanded(id);
    const r = await accountingApi.journalEntry(id);
    setExpandedEntry(r.data);
  };

  const totalPages = Math.max(1, Math.ceil(meta.total / meta.per_page));

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="grid grid-cols-1 gap-3 xs:grid-cols-2 lg:flex lg:flex-wrap lg:items-end">
        <div>
          <label className="block text-xs text-slate-500 mb-1">From</label>
          <input
            type="date"
            value={from}
            onChange={(e) => {
              setFrom(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">To</label>
          <input
            type="date"
            value={to}
            onChange={(e) => {
              setTo(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <button
          onClick={() => {
            setPage(1);
            load();
          }}
          className="min-h-11 rounded-md bg-indigo-600 px-4 py-1.5 text-sm text-white hover:bg-indigo-700"
        >
          Refresh
        </button>
        <span className="text-slate-400 text-sm self-end ml-auto">
          {meta.total} entries
        </span>
      </div>

      {/* Search row */}
      <div className="grid grid-cols-1 gap-3 xs:grid-cols-2 lg:grid-cols-4">
        <div>
          <label className="block text-xs text-slate-500 mb-1">Search description</label>
          <input
            type="text"
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setPage(1);
            }}
            placeholder="text in entry or line description"
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">Account code starts with</label>
          <input
            type="text"
            value={accountCode}
            onChange={(e) => {
              setAccountCode(e.target.value);
              setPage(1);
            }}
            placeholder="e.g. 1100"
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">Min amount</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={minAmount}
            onChange={(e) => {
              setMinAmount(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">Max amount</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={maxAmount}
            onChange={(e) => {
              setMaxAmount(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
      </div>

      {error && <p className="text-red-500 text-sm">{error}</p>}

      {/* Mobile cards */}
      <div className="space-y-2 md:hidden">
        {loading && (
          <p className="text-slate-400 text-sm py-6 text-center">Loading…</p>
        )}
        {!loading && entries.length === 0 && (
          <p className="text-slate-400 text-sm py-6 text-center">
            No entries in this date range
          </p>
        )}
        {entries.map((e) => (
          <div key={e.id} className="space-y-2">
            <MobileRowCard
              title={
                <span className="font-mono text-xs text-slate-800">
                  {e.entry_date}
                </span>
              }
              subtitle={e.description}
              meta={<Badge v={e.status} />}
              fields={[
                {
                  label: "Type",
                  value: e.entry_type ? <Badge v={e.entry_type} /> : "—",
                },
                {
                  label: "Debits",
                  value: (
                    <span className="font-mono">{fmt(e.total_debits)}</span>
                  ),
                },
                {
                  label: "Credits",
                  value: (
                    <span className="font-mono">{fmt(e.total_credits)}</span>
                  ),
                },
              ]}
              actions={
                <button
                  type="button"
                  onClick={() => toggleExpand(e.id)}
                  className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
                >
                  {expanded === e.id ? "Hide lines" : "Show lines"}
                </button>
              }
            />
            {expanded === e.id && expandedEntry && (
              <div className="overflow-x-auto rounded-md border border-slate-200 bg-slate-50 p-3">
                <table className="min-w-full text-xs">
                  <thead>
                    <tr className="text-slate-400 uppercase tracking-wide">
                      <th className="text-left pb-1">Account</th>
                      <th className="text-left pb-1">Side</th>
                      <th className="text-right pb-1">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {(expandedEntry.lines ?? []).map((l) => (
                      <tr key={l.id}>
                        <td className="py-1 font-mono text-slate-600">
                          {l.account_code} — {l.account_name}
                        </td>
                        <td className="py-1">
                          <Badge v={l.side} />
                        </td>
                        <td className="py-1 text-right font-mono">
                          {fmt(l.amount)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Desktop table */}
      <div className="hidden md:block overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
        <table className="min-w-[760px] text-sm">
          <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <SortHeader
                label="Date"
                active={sortKey === "entry_date"}
                dir={sortDir}
                onClick={() => toggleSort("entry_date")}
              />
              <SortHeader
                label="Description"
                active={sortKey === "description"}
                dir={sortDir}
                onClick={() => toggleSort("description")}
              />
              <SortHeader
                label="Type"
                active={sortKey === "entry_type"}
                dir={sortDir}
                onClick={() => toggleSort("entry_type")}
              />
              <SortHeader
                label="Status"
                active={sortKey === "status"}
                dir={sortDir}
                onClick={() => toggleSort("status")}
              />
              <th className="px-4 py-2 text-right">Debits</th>
              <th className="px-4 py-2 text-right">Credits</th>
              <th className="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {loading ? (
              <tr>
                <td
                  colSpan={7}
                  className="px-4 py-6 text-center text-slate-400"
                >
                  Loading…
                </td>
              </tr>
            ) : entries.length === 0 ? (
              <tr>
                <td
                  colSpan={7}
                  className="px-4 py-6 text-center text-slate-400"
                >
                  No entries in this date range
                </td>
              </tr>
            ) : (
              entries.map((e) => (
                <>
                  <tr
                    key={e.id}
                    className="hover:bg-slate-50 cursor-pointer"
                    onClick={() => toggleExpand(e.id)}
                  >
                    <td className="px-4 py-2 font-mono text-slate-600">
                      {e.entry_date}
                    </td>
                    <td className="px-4 py-2 text-slate-800 max-w-xs truncate">
                      {e.description}
                    </td>
                    <td className="px-4 py-2">
                      {e.entry_type ? <Badge v={e.entry_type} /> : "—"}
                    </td>
                    <td className="px-4 py-2">
                      <Badge v={e.status} />
                    </td>
                    <td className="px-4 py-2 text-right font-mono">
                      {fmt(e.total_debits)}
                    </td>
                    <td className="px-4 py-2 text-right font-mono">
                      {fmt(e.total_credits)}
                    </td>
                    <td className="px-4 py-2 text-slate-400 text-xs">
                      {expanded === e.id ? "▲" : "▼"}
                    </td>
                  </tr>
                  {expanded === e.id && expandedEntry && (
                    <tr key={`${e.id}-lines`} className="bg-slate-50">
                      <td colSpan={7} className="px-8 py-3">
                        <div className="overflow-x-auto">
                          <table className="min-w-full text-xs">
                            <thead>
                              <tr className="text-slate-400 uppercase tracking-wide">
                                <th className="text-left pb-1">Account</th>
                                <th className="text-left pb-1">Side</th>
                                <th className="text-right pb-1">Amount</th>
                                <th className="text-left pb-1 pl-4">Note</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-200">
                              {(expandedEntry.lines ?? []).map((l) => (
                                <tr key={l.id}>
                                  <td className="py-1 font-mono text-slate-600">
                                    {l.account_code} — {l.account_name}
                                  </td>
                                  <td className="py-1">
                                    <Badge v={l.side} />
                                  </td>
                                  <td className="py-1 text-right font-mono font-medium">
                                    {fmt(l.amount)}
                                  </td>
                                  <td className="py-1 pl-4 text-slate-500">
                                    {l.description ?? ""}
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination + per-page */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between text-sm text-slate-600">
        <span>
          Page {meta.page} of {totalPages}
        </span>
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2">
            <span className="text-xs text-slate-500">Per page</span>
            <select
              value={perPage}
              onChange={(e) => {
                setPerPage(Number(e.target.value));
                setPage(1);
              }}
              className="min-h-10 rounded border border-slate-300 px-2 text-sm"
            >
              {[10, 25, 50, 100].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </label>
          <button
            disabled={page <= 1}
            onClick={() => setPage(page - 1)}
            className="min-h-10 rounded border px-3 text-sm hover:bg-slate-50 disabled:opacity-40"
          >
            ← Prev
          </button>
          <button
            disabled={page >= totalPages}
            onClick={() => setPage(page + 1)}
            className="min-h-10 rounded border px-3 text-sm hover:bg-slate-50 disabled:opacity-40"
          >
            Next →
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Trial Balance tab ─────────────────────────────────────────────────────────

function TrialBalanceTab() {
  const [asOf, setAsOf] = useState(dateInput(new Date()));
  const [data, setData] = useState<TrialBalance | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [sortKey, setSortKey] = useState<"code" | "name" | "balance">("code");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const load = useCallback(() => {
    setLoading(true);
    accountingApi
      .trialBalance(asOf)
      .then(setData)
      .catch(() => setError("Failed to load trial balance"))
      .finally(() => setLoading(false));
  }, [asOf]);

  useEffect(() => {
    load();
  }, [load]);

  const toggleSort = (key: "code" | "name" | "balance") => {
    if (sortKey === key) setSortDir(nextDir(sortDir));
    else {
      setSortKey(key);
      setSortDir("asc");
    }
  };

  const sortedRows = useMemo(() => {
    if (!data) return [];
    const sorted = [...data.data].sort((a, b) => {
      if (sortKey === "balance") return a.balance - b.balance;
      const av = a[sortKey] ?? "";
      const bv = b[sortKey] ?? "";
      return String(av).localeCompare(String(bv));
    });
    return sortDir === "asc" ? sorted : sorted.reverse();
  }, [data, sortKey, sortDir]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-slate-500 mb-1">As of</label>
          <input
            type="date"
            value={asOf}
            onChange={(e) => setAsOf(e.target.value)}
            className="min-h-11 rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <button
          onClick={load}
          className="min-h-11 rounded-md bg-indigo-600 px-4 py-1.5 text-sm text-white hover:bg-indigo-700"
        >
          Run
        </button>
        {data && (
          <span
            className={`ml-auto text-sm font-medium ${data.balanced ? "text-emerald-600" : "text-red-500"}`}
          >
            {data.balanced ? "✓ Balanced" : "✗ Out of balance"}
          </span>
        )}
      </div>

      {error && <p className="text-red-500 text-sm">{error}</p>}
      {loading && <p className="text-slate-500 text-sm">Loading…</p>}

      {data && !loading && (
        <>
          {/* Mobile cards */}
          <div className="space-y-2 md:hidden">
            {sortedRows.map((r) => (
              <MobileRowCard
                key={r.code}
                title={<span className="font-mono text-sm">{r.code}</span>}
                subtitle={r.name}
                meta={<Badge v={r.account_type} />}
                fields={[
                  {
                    label: "Debits",
                    value: <span className="font-mono">{fmt(r.debits)}</span>,
                  },
                  {
                    label: "Credits",
                    value: <span className="font-mono">{fmt(r.credits)}</span>,
                  },
                  {
                    label: "Balance",
                    value: (
                      <span
                        className={`font-mono font-semibold ${r.balance >= 0 ? "text-slate-800" : "text-red-500"}`}
                      >
                        {fmt(r.balance)}
                      </span>
                    ),
                  },
                ]}
              />
            ))}
            <div className="mt-2 rounded-md bg-slate-100 px-3 py-2 text-xs font-semibold flex justify-between">
              <span>Totals</span>
              <span className="font-mono">
                Dr {fmt(data.totals.debits)} · Cr {fmt(data.totals.credits)}
              </span>
            </div>
          </div>

          {/* Desktop table */}
          <div className="hidden md:block overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
            <table className="min-w-[720px] text-sm">
              <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
                <tr>
                  <SortHeader
                    label="Code"
                    active={sortKey === "code"}
                    dir={sortDir}
                    onClick={() => toggleSort("code")}
                  />
                  <SortHeader
                    label="Account"
                    active={sortKey === "name"}
                    dir={sortDir}
                    onClick={() => toggleSort("name")}
                  />
                  <th className="px-4 py-2 text-left">Type</th>
                  <th className="px-4 py-2 text-right">Debits</th>
                  <th className="px-4 py-2 text-right">Credits</th>
                  <SortHeader
                    label="Balance"
                    active={sortKey === "balance"}
                    dir={sortDir}
                    onClick={() => toggleSort("balance")}
                    align="right"
                  />
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {sortedRows.map((r) => (
                  <tr key={r.code} className="hover:bg-slate-50">
                    <td className="px-4 py-2 font-mono text-slate-500">
                      {r.code}
                    </td>
                    <td className="px-4 py-2 font-medium text-slate-800">
                      {r.name}
                    </td>
                    <td className="px-4 py-2">
                      <Badge v={r.account_type} />
                    </td>
                    <td className="px-4 py-2 text-right font-mono">
                      {fmt(r.debits)}
                    </td>
                    <td className="px-4 py-2 text-right font-mono">
                      {fmt(r.credits)}
                    </td>
                    <td
                      className={`px-4 py-2 text-right font-mono font-semibold ${r.balance >= 0 ? "text-slate-800" : "text-red-500"}`}
                    >
                      {fmt(r.balance)}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-slate-100 text-xs font-semibold">
                <tr>
                  <td
                    colSpan={3}
                    className="px-4 py-2 text-slate-600 uppercase tracking-wide"
                  >
                    Totals
                  </td>
                  <td className="px-4 py-2 text-right font-mono">
                    {fmt(data.totals.debits)}
                  </td>
                  <td className="px-4 py-2 text-right font-mono">
                    {fmt(data.totals.credits)}
                  </td>
                  <td className="px-4 py-2"></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

// ── P&L tab ───────────────────────────────────────────────────────────────────

function PnlTab() {
  const today = new Date();
  const [from, setFrom] = useState(
    dateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
  );
  const [to, setTo] = useState(dateInput(today));
  const [data, setData] = useState<Pnl | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const load = useCallback(() => {
    setLoading(true);
    accountingApi
      .pnl(from, to)
      .then(setData)
      .catch(() => setError("Failed to load P&L"))
      .finally(() => setLoading(false));
  }, [from, to]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-slate-500 mb-1">From</label>
          <input
            type="date"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
            className="border rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">To</label>
          <input
            type="date"
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="border rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <button
          onClick={load}
          className="bg-indigo-600 text-white px-4 py-1.5 rounded-md text-sm hover:bg-indigo-700"
        >
          Run
        </button>
      </div>

      {error && <p className="text-red-500 text-sm">{error}</p>}
      {loading && <p className="text-slate-500 text-sm">Loading…</p>}

      {data && !loading && (
        <div className="grid gap-6 lg:grid-cols-2">
          {/* Revenue */}
          <div className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
            <div className="bg-emerald-50 px-4 py-2 border-b border-slate-200">
              <h3 className="font-semibold text-emerald-700 text-sm">
                Revenue
              </h3>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <tbody className="divide-y divide-slate-100">
                  {data.revenue.length === 0 && (
                    <tr>
                      <td className="px-4 py-3 text-slate-400 text-center">
                        No revenue
                      </td>
                    </tr>
                  )}
                  {data.revenue.map((r) => (
                    <tr key={r.code} className="hover:bg-slate-50">
                      <td className="px-4 py-2 font-mono text-slate-500">
                        {r.code}
                      </td>
                      <td className="px-4 py-2 text-slate-700">{r.name}</td>
                      <td className="px-4 py-2 text-right font-mono font-medium text-emerald-700">
                        {fmt(r.amount)}
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="bg-emerald-50 text-sm font-semibold">
                  <tr>
                    <td colSpan={2} className="px-4 py-2 text-emerald-700">
                      Total Revenue
                    </td>
                    <td className="px-4 py-2 text-right font-mono text-emerald-700">
                      {fmt(data.total_revenue)}
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>

          {/* Expenses */}
          <div className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
            <div className="bg-red-50 px-4 py-2 border-b border-slate-200">
              <h3 className="font-semibold text-red-700 text-sm">Expenses</h3>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <tbody className="divide-y divide-slate-100">
                  {data.expenses.length === 0 && (
                    <tr>
                      <td className="px-4 py-3 text-slate-400 text-center">
                        No expenses
                      </td>
                    </tr>
                  )}
                  {data.expenses.map((r) => (
                    <tr key={r.code} className="hover:bg-slate-50">
                      <td className="px-4 py-2 font-mono text-slate-500">
                        {r.code}
                      </td>
                      <td className="px-4 py-2 text-slate-700">{r.name}</td>
                      <td className="px-4 py-2 text-right font-mono font-medium text-red-700">
                        {fmt(r.amount)}
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="bg-red-50 text-sm font-semibold">
                  <tr>
                    <td colSpan={2} className="px-4 py-2 text-red-700">
                      Total Expenses
                    </td>
                    <td className="px-4 py-2 text-right font-mono text-red-700">
                      {fmt(data.total_expenses)}
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>

          {/* Net Income */}
          <div
            className={`flex flex-col gap-2 rounded-lg border px-4 py-4 shadow-sm sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:col-span-2
            ${data.net_income >= 0 ? "bg-emerald-50 border-emerald-200" : "bg-red-50 border-red-200"}`}
          >
            <span
              className={`font-semibold text-base ${data.net_income >= 0 ? "text-emerald-800" : "text-red-800"}`}
            >
              Net Income ({data.from} → {data.to})
            </span>
            <span
              className={`font-bold text-xl font-mono ${data.net_income >= 0 ? "text-emerald-700" : "text-red-700"}`}
            >
              {fmt(data.net_income)}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Balance Sheet tab ─────────────────────────────────────────────────────────

function BalanceSheetTab() {
  const [asOf, setAsOf] = useState<string>(
    new Date().toISOString().slice(0, 10),
  );
  const [data, setData] = useState<BalanceSheet | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    accountingApi
      .balanceSheet(asOf)
      .then((d) => setData(d))
      .catch(() => setError("Failed to load balance sheet"))
      .finally(() => setLoading(false));
  }, [asOf]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <label className="text-sm text-slate-600">As of</label>
        <input
          type="date"
          value={asOf}
          onChange={(e) => setAsOf(e.target.value)}
          className="min-h-11 rounded border px-2 py-1 text-sm"
        />
      </div>

      {error && (
        <div className="bg-red-100 text-red-700 p-2 rounded text-sm">
          {error}
        </div>
      )}
      {loading && <div className="text-sm text-slate-500">Loading…</div>}

      {data && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <section className="bg-white rounded shadow overflow-hidden">
            <header className="bg-emerald-50 px-3 py-2 text-sm font-semibold">
              Assets
            </header>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <tbody>
                  {data.assets.rows.map((r) => (
                    <tr key={r.code} className="border-t">
                      <td className="px-3 py-1 font-mono text-xs">{r.code}</td>
                      <td className="px-3 py-1">{r.name}</td>
                      <td className="px-3 py-1 text-right">{fmt(r.balance)}</td>
                    </tr>
                  ))}
                  <tr className="border-t bg-emerald-50 font-semibold">
                    <td colSpan={2} className="px-3 py-1 text-right">
                      Total assets
                    </td>
                    <td className="px-3 py-1 text-right">
                      {fmt(data.assets.total)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section className="bg-white rounded shadow overflow-hidden">
            <header className="bg-amber-50 px-3 py-2 text-sm font-semibold">
              Liabilities + Equity
            </header>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <tbody>
                  {data.liabilities.rows.map((r) => (
                    <tr key={r.code} className="border-t">
                      <td className="px-3 py-1 font-mono text-xs">{r.code}</td>
                      <td className="px-3 py-1">{r.name}</td>
                      <td className="px-3 py-1 text-right">{fmt(r.balance)}</td>
                    </tr>
                  ))}
                  <tr className="border-t bg-amber-50 font-medium">
                    <td colSpan={2} className="px-3 py-1 text-right">
                      Total liabilities
                    </td>
                    <td className="px-3 py-1 text-right">
                      {fmt(data.liabilities.total)}
                    </td>
                  </tr>
                  {data.equity.rows.map((r) => (
                    <tr key={r.code} className="border-t">
                      <td className="px-3 py-1 font-mono text-xs">{r.code}</td>
                      <td className="px-3 py-1">{r.name}</td>
                      <td className="px-3 py-1 text-right">{fmt(r.balance)}</td>
                    </tr>
                  ))}
                  <tr className="border-t">
                    <td className="px-3 py-1 font-mono text-xs">—</td>
                    <td className="px-3 py-1 italic">Retained earnings</td>
                    <td className="px-3 py-1 text-right">
                      {fmt(data.equity.retained_earnings)}
                    </td>
                  </tr>
                  <tr className="border-t bg-amber-50 font-semibold">
                    <td colSpan={2} className="px-3 py-1 text-right">
                      Total liab + equity
                    </td>
                    <td className="px-3 py-1 text-right">
                      {fmt(data.total_liab_equity)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      )}

      {data && !data.balanced && (
        <div className="bg-red-100 text-red-700 p-2 rounded text-sm">
          Balance sheet is NOT balanced (assets ≠ liab + equity).
        </div>
      )}
      {data && data.balanced && (
        <div className="bg-emerald-50 text-emerald-700 p-2 rounded text-sm">
          Balanced ✓
        </div>
      )}
    </div>
  );
}

// ── Manual entry tab ──────────────────────────────────────────────────────────

interface ManualLine {
  account_code: string;
  side: "debit" | "credit";
  amount: string;
  description: string;
  supplier_id: string;
}

function ManualEntryTab({ onPosted }: { onPosted: () => void }) {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [accountQuery, setAccountQuery] = useState("");
  const [materialSuppliers, setMaterialSuppliers] = useState<Supplier[]>([]);
  const [entryDate, setEntryDate] = useState(() =>
    new Date().toISOString().slice(0, 10),
  );
  const [description, setDescription] = useState("");
  const [currency, setCurrency] = useState("EGP");
  const [lines, setLines] = useState<ManualLine[]>([
    {
      account_code: "",
      side: "debit",
      amount: "",
      description: "",
      supplier_id: "",
    },
    {
      account_code: "",
      side: "credit",
      amount: "",
      description: "",
      supplier_id: "",
    },
  ]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // Debounced search across the chart of accounts.
  useEffect(() => {
    const t = setTimeout(() => {
      accountingApi
        .accounts(accountQuery ? { q: accountQuery } : undefined)
        .then((r) => setAccounts(r.data))
        .catch(() => undefined);
    }, 200);
    return () => clearTimeout(t);
  }, [accountQuery]);

  useEffect(() => {
    suppliersApi
      .list({ per_page: 200, kind: "material" })
      .then((r) => setMaterialSuppliers(r.data))
      .catch(() => undefined);
  }, []);

  const debitTotal = lines
    .filter((l) => l.side === "debit")
    .reduce((s, l) => s + Number(l.amount || 0), 0);
  const creditTotal = lines
    .filter((l) => l.side === "credit")
    .reduce((s, l) => s + Number(l.amount || 0), 0);
  const balanced = Math.abs(debitTotal - creditTotal) < 0.005 && debitTotal > 0;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    if (!balanced) {
      setError("Debits must equal credits and be > 0");
      return;
    }
    const valid = lines.filter((l) => l.account_code && Number(l.amount) > 0);
    if (valid.length < 2) {
      setError("Need at least 2 lines with account & amount");
      return;
    }
    setSubmitting(true);
    try {
      await accountingApi.createJournalEntry({
        entry_date: entryDate,
        description,
        currency,
        entry_type: "manual",
        lines: valid.map((l) => ({
          account_code: l.account_code,
          side: l.side,
          amount: Number(l.amount).toFixed(2),
          description: l.description || undefined,
          supplier_id: l.supplier_id || undefined,
        })),
      });
      setSuccess("Posted ✔");
      setDescription("");
      setLines([
        {
          account_code: "",
          side: "debit",
          amount: "",
          description: "",
          supplier_id: "",
        },
        {
          account_code: "",
          side: "credit",
          amount: "",
          description: "",
          supplier_id: "",
        },
      ]);
      setTimeout(() => {
        onPosted();
      }, 700);
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data
          ?.error || (e as Error).message;
      setError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="w-full max-w-4xl rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
      <h2 className="text-lg font-semibold text-slate-800 mb-1">
        New manual journal entry
      </h2>
      <p className="text-xs text-slate-500 mb-4">
        Post any double-entry transaction. Debits must equal credits.
      </p>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          <label className="text-sm">
            <span className="block text-slate-600 mb-1">Date *</span>
            <input
              type="date"
              required
              value={entryDate}
              onChange={(e) => setEntryDate(e.target.value)}
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
          <label className="text-sm md:col-span-2">
            <span className="block text-slate-600 mb-1">Description *</span>
            <input
              required
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="e.g. Owner cash injection"
              className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
        </div>

        <label className="text-sm block max-w-xs">
          <span className="block text-slate-600 mb-1">Currency</span>
          <input
            value={currency}
            onChange={(e) => setCurrency(e.target.value.toUpperCase())}
            maxLength={3}
            className="min-h-11 w-full rounded border border-slate-300 px-3 py-2 uppercase"
          />
        </label>

        <div className="rounded border border-slate-200">
          <div className="px-2 py-2 border-b border-slate-200 bg-slate-50">
            <input
              type="search"
              value={accountQuery}
              onChange={(e) => setAccountQuery(e.target.value)}
              placeholder="Filter accounts by code or name…"
              className="w-full max-w-xs rounded border border-slate-300 px-2 py-1 text-sm"
            />
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-[820px] text-sm">
              <thead className="bg-slate-50 text-xs text-slate-600 uppercase">
                <tr>
                  <th className="px-2 py-2 text-left">Account</th>
                  <th className="px-2 py-2 text-left w-24">Side</th>
                  <th className="px-2 py-2 text-right w-32">Amount</th>
                  <th className="px-2 py-2 text-left w-48">
                    Supplier (material)
                  </th>
                  <th className="px-2 py-2 text-left">Memo</th>
                  <th className="w-8"></th>
                </tr>
              </thead>
              <tbody>
                {lines.map((l, idx) => (
                  <tr key={idx} className="border-t border-slate-100">
                    <td className="px-2 py-1">
                      <select
                        value={l.account_code}
                        onChange={(e) =>
                          setLines((arr) =>
                            arr.map((x, i) =>
                              i === idx
                                ? { ...x, account_code: e.target.value }
                                : x,
                            ),
                          )
                        }
                        className="w-full border border-slate-200 rounded px-2 py-1"
                      >
                        <option value="">—</option>
                        {accounts.map((a) => (
                          <option key={a.code} value={a.code}>
                            {a.code} — {a.name}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-2 py-1">
                      <select
                        value={l.side}
                        onChange={(e) =>
                          setLines((arr) =>
                            arr.map((x, i) =>
                              i === idx
                                ? {
                                    ...x,
                                    side: e.target.value as "debit" | "credit",
                                  }
                                : x,
                            ),
                          )
                        }
                        className="w-full border border-slate-200 rounded px-2 py-1"
                      >
                        <option value="debit">Debit</option>
                        <option value="credit">Credit</option>
                      </select>
                    </td>
                    <td className="px-2 py-1">
                      <input
                        type="number"
                        step="0.01"
                        min={0}
                        value={l.amount}
                        onChange={(e) =>
                          setLines((arr) =>
                            arr.map((x, i) =>
                              i === idx ? { ...x, amount: e.target.value } : x,
                            ),
                          )
                        }
                        className="w-full border border-slate-200 rounded px-2 py-1 text-right"
                      />
                    </td>
                    <td className="px-2 py-1">
                      <select
                        value={l.supplier_id}
                        onChange={(e) =>
                          setLines((arr) =>
                            arr.map((x, i) =>
                              i === idx
                                ? { ...x, supplier_id: e.target.value }
                                : x,
                            ),
                          )
                        }
                        className="w-full border border-slate-200 rounded px-2 py-1"
                      >
                        <option value="">—</option>
                        {materialSuppliers.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.supplier_code ? `${s.supplier_code} - ` : ""}
                            {s.name}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-2 py-1">
                      <input
                        value={l.description}
                        onChange={(e) =>
                          setLines((arr) =>
                            arr.map((x, i) =>
                              i === idx
                                ? { ...x, description: e.target.value }
                                : x,
                            ),
                          )
                        }
                        className="w-full border border-slate-200 rounded px-2 py-1"
                      />
                    </td>
                    <td className="px-2 py-1 text-center">
                      <button
                        type="button"
                        onClick={() =>
                          setLines((arr) => arr.filter((_, i) => i !== idx))
                        }
                        disabled={lines.length <= 2}
                        className="text-red-500 hover:text-red-700 text-sm disabled:text-slate-300"
                      >
                        ×
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-slate-50 text-xs">
                <tr className="border-t border-slate-200">
                  <td
                    colSpan={2}
                    className="px-2 py-2 text-right font-medium text-slate-600"
                  >
                    Totals
                  </td>
                  <td className="px-2 py-2 text-right">
                    <span className="text-slate-700">
                      Dr {debitTotal.toFixed(2)}
                    </span>
                    <br />
                    <span className="text-slate-700">
                      Cr {creditTotal.toFixed(2)}
                    </span>
                  </td>
                  <td colSpan={2} className="px-2 py-2">
                    {balanced ? (
                      <span className="text-emerald-600 font-medium">
                        Balanced ✔
                      </span>
                    ) : (
                      <span className="text-amber-600">
                        Diff {(debitTotal - creditTotal).toFixed(2)}
                      </span>
                    )}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
          <button
            type="button"
            onClick={() =>
              setLines((arr) => [
                ...arr,
                {
                  account_code: "",
                  side: "debit",
                  amount: "",
                  description: "",
                  supplier_id: "",
                },
              ])
            }
            className="min-h-10 w-full border-t border-slate-200 py-1.5 text-xs text-indigo-600 hover:bg-indigo-50"
          >
            + Add line
          </button>
        </div>

        {error && (
          <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
            {error}
          </div>
        )}
        {success && (
          <div className="bg-emerald-50 text-emerald-700 text-sm p-2 rounded">
            {success}
          </div>
        )}

        <div className="flex justify-end">
          <button
            type="submit"
            disabled={submitting || !balanced}
            className="min-h-11 rounded bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:bg-slate-400"
          >
            {submitting ? "Posting…" : "Post entry"}
          </button>
        </div>
      </form>
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

function AccountLedgerTab() {
  const today = new Date();
  const [code, setCode] = useState("");
  const [from, setFrom] = useState(
    dateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
  );
  const [to, setTo] = useState(dateInput(today));
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<AccountLedgerRow[]>([]);
  const [meta, setMeta] = useState<{
    page: number;
    per_page: number;
    total: number;
    account?: Account;
  }>({ page: 1, per_page: 50, total: 0 });
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(() => {
    if (!code.trim()) {
      setRows([]);
      setMeta({ page: 1, per_page: 50, total: 0 });
      return;
    }
    setLoading(true);
    setError("");
    accountingApi
      .accountLedger(code.trim(), {
        from,
        to,
        q: q || undefined,
        page,
        per_page: 50,
      })
      .then((r) => {
        setRows(r.data);
        setMeta(r.meta);
      })
      .catch(() => setError("Failed to load ledger (check account code)"))
      .finally(() => setLoading(false));
  }, [code, from, to, q, page]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(meta.total / meta.per_page));

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-3 xs:grid-cols-2 lg:flex lg:flex-wrap lg:items-end">
        <div>
          <label className="block text-xs text-slate-500 mb-1">Account code</label>
          <input
            type="text"
            value={code}
            onChange={(e) => {
              setCode(e.target.value);
              setPage(1);
            }}
            placeholder="e.g. 1100"
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">From</label>
          <input
            type="date"
            value={from}
            onChange={(e) => {
              setFrom(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div>
          <label className="block text-xs text-slate-500 mb-1">To</label>
          <input
            type="date"
            value={to}
            onChange={(e) => {
              setTo(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div className="flex-1 min-w-[180px]">
          <label className="block text-xs text-slate-500 mb-1">Search description</label>
          <input
            type="text"
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setPage(1);
            }}
            className="min-h-11 w-full rounded-md border px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <span className="text-slate-400 text-sm self-end ml-auto">
          {meta.total} lines
        </span>
      </div>

      {meta.account && (
        <div className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
          <span className="font-mono text-slate-800">{meta.account.code}</span>{" "}
          <span className="font-semibold">{meta.account.name}</span>{" "}
          <span className="text-slate-500">
            ({meta.account.account_type}, normal {meta.account.normal_side})
          </span>
        </div>
      )}

      {error && <p className="text-red-500 text-sm">{error}</p>}

      <div className="overflow-x-auto rounded-md border border-slate-200">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-slate-600">
            <tr>
              <th className="px-3 py-2 text-left">Date</th>
              <th className="px-3 py-2 text-left">Entry</th>
              <th className="px-3 py-2 text-left">Line description</th>
              <th className="px-3 py-2 text-right">Debit</th>
              <th className="px-3 py-2 text-right">Credit</th>
              <th className="px-3 py-2 text-right">Running balance</th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr>
                <td colSpan={6} className="py-6 text-center text-slate-400">
                  Loading…
                </td>
              </tr>
            )}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={6} className="py-6 text-center text-slate-400">
                  {code.trim() ? "No lines in this range" : "Enter an account code to begin"}
                </td>
              </tr>
            )}
            {rows.map((r) => (
              <tr key={r.line_id} className="border-t border-slate-100">
                <td className="px-3 py-2 font-mono text-xs">{r.entry_date}</td>
                <td className="px-3 py-2">{r.entry_description}</td>
                <td className="px-3 py-2 text-slate-600">{r.description ?? "—"}</td>
                <td className="px-3 py-2 text-right font-mono">
                  {r.side === "debit" ? fmt(r.amount) : ""}
                </td>
                <td className="px-3 py-2 text-right font-mono">
                  {r.side === "credit" ? fmt(r.amount) : ""}
                </td>
                <td className="px-3 py-2 text-right font-mono">
                  {fmt(r.running_balance)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {meta.total > 0 && (
        <div className="flex items-center justify-between text-sm">
          <button
            disabled={page <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            className="rounded-md border px-3 py-1 disabled:opacity-50"
          >
            Prev
          </button>
          <span className="text-slate-500">
            Page {page} of {totalPages}
          </span>
          <button
            disabled={page >= totalPages}
            onClick={() => setPage((p) => p + 1)}
            className="rounded-md border px-3 py-1 disabled:opacity-50"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}

type Tab =
  | "journal"
  | "manual_entry"
  | "coa"
  | "ledger"
  | "trial_balance"
  | "pnl"
  | "balance_sheet";

export default function AccountingPage() {
  const [tab, setTab] = useState<Tab>("journal");

  const tabs: { id: Tab; label: string }[] = [
    { id: "journal", label: "Journal Entries" },
    { id: "manual_entry", label: "+ Manual Entry" },
    { id: "coa", label: "Chart of Accounts" },
    { id: "ledger", label: "Account Ledger" },
    { id: "trial_balance", label: "Trial Balance" },
    { id: "pnl", label: "P & L" },
    { id: "balance_sheet", label: "Balance Sheet" },
  ];

  return (
    <PageContainer className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Accounting</h1>
        <p className="text-slate-500 text-sm mt-1">
          Double-entry ledger, trial balance, and income statement
        </p>
      </div>

      {/* Tab bar */}
      <Tabs tabs={tabs} value={tab} onChange={setTab} />

      {tab === "journal" && <JournalTab />}
      {tab === "manual_entry" && (
        <ManualEntryTab onPosted={() => setTab("journal")} />
      )}
      {tab === "coa" && <AccountsTab />}
      {tab === "ledger" && <AccountLedgerTab />}
      {tab === "trial_balance" && <TrialBalanceTab />}
      {tab === "pnl" && <PnlTab />}
      {tab === "balance_sheet" && <BalanceSheetTab />}
    </PageContainer>
  );
}
