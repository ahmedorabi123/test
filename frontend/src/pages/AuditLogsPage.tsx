import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { auditLogsApi, type AuditLogEntry } from "../api/audit_logs";

export default function AuditLogsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = 50;
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
  }, [page, action, subjectType, userId]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(total / perPage));

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">Audit logs</h1>
        <p className="text-sm text-slate-500 mt-1">
          {total.toLocaleString()} entries · admin only
        </p>
      </div>

      <div className="flex items-center gap-2">
        <input
          type="text"
          placeholder="Action (e.g. customer.create)"
          value={action}
          onChange={(e) => {
            setParam("page", "1");
            setParam("action_type", e.target.value);
          }}
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm w-64"
        />
        <input
          type="text"
          placeholder="Subject type (e.g. Customer)"
          value={subjectType}
          onChange={(e) => {
            setParam("page", "1");
            setParam("subject_type", e.target.value);
          }}
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm w-64"
        />
      </div>

      {error && (
        <div className="bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {error}
        </div>
      )}

      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
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

      <div className="flex items-center justify-between text-sm text-slate-600">
        <span>
          Page {page} of {totalPages}
        </span>
        <div className="flex items-center gap-2">
          <button
            disabled={page <= 1}
            onClick={() => setParam("page", String(page - 1))}
            className="px-3 py-1 border border-slate-300 rounded-md disabled:opacity-40"
          >
            ← Prev
          </button>
          <button
            disabled={page >= totalPages}
            onClick={() => setParam("page", String(page + 1))}
            className="px-3 py-1 border border-slate-300 rounded-md disabled:opacity-40"
          >
            Next →
          </button>
        </div>
      </div>
    </div>
  );
}
