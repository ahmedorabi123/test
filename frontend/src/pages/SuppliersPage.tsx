import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { suppliersApi, type Supplier } from "../api/suppliers";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

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
  const debouncedSearch = useDebouncedValue(searchInput, 300);

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (value == null || value === "") sp.delete(key);
    else sp.set(key, value);
    setSearchParams(sp, { replace: true });
  };

  // Push debounced search into URL on change.
  useEffect(() => {
    if (debouncedSearch === search) return;
    const sp = new URLSearchParams(searchParams);
    if (debouncedSearch) sp.set("search", debouncedSearch);
    else sp.delete("search");
    sp.set("page", "1");
    setSearchParams(sp, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch]);

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
        id: "supplier_code",
        header: "Code",
        sortKey: "supplier_code",
        render: (s) => (
          <span className="font-mono text-xs text-slate-600">
            {s.supplier_code || "-"}
          </span>
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
                : s.status === "on_hold"
                  ? "bg-amber-50 text-amber-700 ring-amber-600/20"
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
    <PageContainer className="space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Suppliers</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total
          </p>
        </div>
        <div className="grid w-full grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:w-auto lg:flex-wrap lg:items-center lg:justify-end">
          <input
            type="text"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search name, email…"
            className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-64"
          />
          <select
            value={status}
            onChange={(e) => {
              setParam("page", "1");
              setParam("status", e.target.value);
            }}
            className="min-h-11 rounded-lg border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="on_hold">On hold</option>
            <option value="inactive">Inactive</option>
          </select>
          <Link
            to="/suppliers/new"
            className="inline-flex min-h-11 items-center justify-center gap-1 rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
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
        mobileCardRenderer={(supplier, context) => (
          <MobileRowCard
            title={
              <Link
                to={`/suppliers/${supplier.id}`}
                className="font-medium text-slate-900 hover:underline"
              >
                {supplier.name}
              </Link>
            }
            subtitle={supplier.email || supplier.phone || "No contact details"}
            meta={supplier.currency}
            selectedControl={
              <input
                type="checkbox"
                checked={context.checked}
                onChange={context.toggleSelected}
                onClick={(event) => event.stopPropagation()}
                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                aria-label={`Select supplier ${supplier.name}`}
              />
            }
            fields={[
              { label: "Code", value: supplier.supplier_code || "-" },
              { label: "Phone", value: supplier.phone || "-" },
              {
                label: "Status",
                value: (
                  <span
                    className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
                      supplier.status === "active"
                        ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
                        : supplier.status === "on_hold"
                          ? "bg-amber-50 text-amber-700 ring-amber-600/20"
                          : "bg-gray-100 text-gray-600 ring-gray-500/20"
                    }`}
                  >
                    {supplier.status}
                  </span>
                ),
              },
            ]}
            actions={
              <Link
                to={`/suppliers/${supplier.id}`}
                className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
              >
                Open supplier
              </Link>
            }
          />
        )}
        syncToUrl={false}
      />
    </PageContainer>
  );
}
