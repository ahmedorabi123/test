import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { suppliersApi, type Supplier } from "../api/suppliers";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";

export default function SuppliersPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "name";
  const sortDir = (searchParams.get("dir") || "asc") as SortDir;
  const search = searchParams.get("search") || "";
  const status = searchParams.get("status") || "";

  const [rows, setRows] = useState<Supplier[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState(search);

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
      const res = await suppliersApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        status: status || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(res.data);
      setTotal(res.meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load suppliers");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, search, status, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Supplier>[]>(
    () => [
      {
        id: "name",
        header: "Name",
        sortKey: "name",
        render: (s) => (
          <Link
            to={`/suppliers/${s.id}`}
            className="font-medium text-slate-900 hover:underline"
          >
            {s.name}
          </Link>
        ),
      },
      {
        id: "email",
        header: "Email",
        sortKey: "email",
        render: (s) => s.email || "—",
      },
      { id: "phone", header: "Phone", render: (s) => s.phone || "—" },
      { id: "currency", header: "Currency", render: (s) => s.currency },
      {
        id: "status",
        header: "Status",
        render: (s) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              s.status === "active"
                ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
                : "bg-gray-100 text-gray-600 ring-gray-500/20"
            }`}
          >
            {s.status}
          </span>
        ),
      },
    ],
    [],
  );

  const bulkActions = useMemo<BulkAction<Supplier>[]>(
    () => [
      {
        id: "activate",
        label: "Activate",
        run: async (sel) => {
          await suppliersApi.bulk(
            sel.map((s) => s.id),
            "activate",
          );
          await load();
        },
      },
      {
        id: "deactivate",
        label: "Deactivate",
        destructive: true,
        run: async (sel) => {
          if (!window.confirm(`Deactivate ${sel.length} supplier(s)?`))
            return false;
          await suppliersApi.bulk(
            sel.map((s) => s.id),
            "deactivate",
          );
          await load();
        },
      },
    ],
    [load],
  );

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Suppliers</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                setParam("page", "1");
                setParam("search", searchInput);
              }
            }}
            placeholder="Search name, email…"
            className="w-64 border border-slate-300 rounded-lg px-3 py-2 text-sm"
          />
          <select
            value={status}
            onChange={(e) => {
              setParam("page", "1");
              setParam("status", e.target.value);
            }}
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </select>
          <Link
            to="/suppliers/new"
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + New supplier
          </Link>
        </div>
      </div>

      <DataTable<Supplier>
        rows={rows}
        columns={columns}
        loading={loading}
        error={error}
        total={total}
        page={page}
        perPage={perPage}
        onPageChange={(p) => setParam("page", String(p))}
        onPerPageChange={(pp) => {
          setParam("page", "1");
          setParam("per_page", String(pp));
        }}
        sort={{ key: sortKey, dir: sortDir }}
        onSortChange={(s) => {
          const sp = new URLSearchParams(searchParams);
          if (s) {
            sp.set("sort", s.key);
            sp.set("dir", s.dir);
          } else {
            sp.delete("sort");
            sp.delete("dir");
          }
          sp.set("page", "1");
          setSearchParams(sp, { replace: true });
        }}
        selectable
        bulkActions={bulkActions}
        syncToUrl={false}
      />
    </div>
  );
}
