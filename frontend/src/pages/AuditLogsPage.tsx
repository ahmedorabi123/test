import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { auditLogsApi, type AuditLogEntry } from "../api/audit_logs";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";

export default function AuditLogsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = (() => {
    const raw = parseInt(searchParams.get("per_page") || "50", 10);
    if (![25, 50, 100].includes(raw)) return 50;
    return raw;
  })();
  const action = searchParams.get("action_type") || "";
  const subjectType = searchParams.get("subject_type") || "";
  const userId = searchParams.get("user_id") || "";

  const [rows, setRows] = useState<AuditLogEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (value == null || value === "") sp.delete(key);
    else sp.set(key, value);
    setSearchParams(sp, { replace: true });
  };

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await auditLogsApi.list({
        page,
        per_page: perPage,
        action_type: action || undefined,
        subject_type: subjectType || undefined,
        user_id: userId || undefined,
      });
      setRows(res.data);
      setTotal(res.meta.total);
    } catch (e: unknown) {
      const err = e as { response?: { status?: number }; message?: string };
      if (err.response?.status === 403) {
        setError("You don't have permission to view audit logs.");
      } else {
        setError(err.message || "Failed to load");
      }
    } finally {
      setLoading(false);
    }
  }, [page, perPage, action, subjectType, userId]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(total / perPage));

  return (
    <PageContainer className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">Audit logs</h1>
        <p className="text-sm text-slate-500 mt-1">
          {total.toLocaleString()} entries · admin only
        </p>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:items-center">
        <input
          type="text"
          placeholder="Action (e.g. customer.create)"
          value={action}
          onChange={(e) => {
            setParam("page", "1");
            setParam("action_type", e.target.value);
          }}
          className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-64"
        />
        <input
          type="text"
          placeholder="Subject type (e.g. Customer)"
          value={subjectType}
          onChange={(e) => {
            setParam("page", "1");
            setParam("subject_type", e.target.value);
          }}
          className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-64"
        />
      </div>

      {error && (
        <div className="bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <div className="rounded-xl border border-slate-200 bg-white">
        <div className="space-y-3 p-3 md:hidden">
          {loading && <div className="py-8 text-center text-sm text-slate-400">Loading…</div>}
          {!loading && rows.length === 0 && (
            <div className="py-8 text-center text-sm text-slate-400">No audit entries</div>
          )}
          {rows.map((row) => {
            const open = expandedId === row.id;
            return (
              <div key={row.id} className="space-y-2">
                <MobileRowCard
                  title={<span className="font-mono text-xs">{row.action}</span>}
                  subtitle={row.user?.email || "system"}
                  meta={new Date(row.occurred_at).toLocaleDateString()}
                  fields={[
                    { label: "Subject", value: row.subject_type || "-" },
                    { label: "Subject ID", value: row.subject_id ? `${row.subject_id.slice(0, 8)}...` : "-" },
                    { label: "IP", value: row.ip_address || "-" },
                  ]}
                  actions={
                    <button
                      type="button"
                      onClick={() => setExpandedId(open ? null : row.id)}
                      className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
                    >
                      {open ? "Hide details" : "Show details"}
                    </button>
                  }
                />
                {open && (
                  <pre className="overflow-x-auto rounded-md border border-slate-200 bg-white p-3 text-xs">
                    {JSON.stringify(row.diff ?? {}, null, 2)}
                  </pre>
                )}
              </div>
            );
          })}
        </div>
        <div className="hidden overflow-x-auto md:block">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50 text-xs uppercase tracking-wider text-slate-500">
            <tr>
              <th className="px-4 py-3 text-left font-medium">When</th>
              <th className="px-4 py-3 text-left font-medium">Actor</th>
              <th className="px-4 py-3 text-left font-medium">Action</th>
              <th className="px-4 py-3 text-left font-medium">Subject</th>
              <th className="px-4 py-3 text-left font-medium">IP</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {loading && (
              <tr>
                <td
                  colSpan={6}
                  className="px-4 py-10 text-center text-slate-400"
                >
                  Loading…
                </td>
              </tr>
            )}
            {!loading && rows.length === 0 && (
              <tr>
                <td
                  colSpan={6}
                  className="px-4 py-10 text-center text-slate-400"
                >
                  No audit entries
                </td>
              </tr>
            )}
            {rows.map((row) => {
              const open = expandedId === row.id;
              return (
                <>
                  <tr
                    key={row.id}
                    className="hover:bg-slate-50 cursor-pointer"
                    onClick={() => setExpandedId(open ? null : row.id)}
                  >
                    <td className="px-4 py-3 whitespace-nowrap text-xs text-slate-600">
                      {new Date(row.occurred_at).toLocaleString()}
                    </td>
                    <td className="px-4 py-3">
                      {row.user?.email || (
                        <span className="text-slate-400">system</span>
                      )}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs">
                      {row.action}
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-600">
                      {row.subject_type}
                      {row.subject_id ? (
                        <span className="text-slate-400 ml-1">
                          #{row.subject_id.slice(0, 8)}…
                        </span>
                      ) : null}
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-500">
                      {row.ip_address || "—"}
                    </td>
                    <td className="px-4 py-3 text-xs text-indigo-600">
                      {open ? "hide" : "details"}
                    </td>
                  </tr>
                  {open && (
                    <tr key={`${row.id}-detail`} className="bg-slate-50">
                      <td colSpan={6} className="px-4 py-3">
                        <pre className="text-xs bg-white border border-slate-200 rounded-md p-3 overflow-x-auto">
                          {JSON.stringify(row.diff ?? {}, null, 2)}
                        </pre>
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
        </div>
      </div>

      <div className="flex flex-col gap-3 text-sm text-slate-600 sm:flex-row sm:items-center sm:justify-between">
        <span>
          Page {page} of {totalPages}
        </span>
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2">
            <span className="text-xs text-slate-500">Per page</span>
            <select
              value={perPage}
              onChange={(e) => {
                const sp = new URLSearchParams(searchParams);
                sp.set("per_page", e.target.value);
                sp.set("page", "1");
                setSearchParams(sp, { replace: true });
              }}
              className="min-h-10 rounded border border-slate-300 px-2 text-sm"
            >
              {[25, 50, 100].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </label>
          <button
            disabled={page <= 1}
            onClick={() => setParam("page", String(page - 1))}
            className="min-h-10 rounded-md border border-slate-300 px-3 disabled:opacity-40"
          >
            ← Prev
          </button>
          <button
            disabled={page >= totalPages}
            onClick={() => setParam("page", String(page + 1))}
            className="min-h-10 rounded-md border border-slate-300 px-3 disabled:opacity-40"
          >
            Next →
          </button>
        </div>
      </div>
    </PageContainer>
  );
}
