import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { customersApi, type Customer } from "../api/customers";
import DataTable, {
  type Column,
  type BulkAction,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";

export default function CustomersPage() {
  const [rows, setRows] = useState<Customer[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const search = searchParams.get("search") || "";

  const [searchInput, setSearchInput] = useState(search);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, meta } = await customersApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load customers");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, sortKey, sortDir, search]);

  useEffect(() => {
    load();
  }, [load]);

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (value == null || value === "") sp.delete(key);
    else sp.set(key, value);
    setSearchParams(sp, { replace: true });
  };

  const columns = useMemo<Column<Customer>[]>(
    () => [
      {
        id: "name",
        header: "Customer name",
        sortKey: "first_name",
        render: (c) => (
          <Link
            to={`/customers/${c.id}`}
            className="font-medium text-indigo-700 hover:underline"
          >
            {c.display_name || c.email || "—"}
          </Link>
        ),
      },
      {
        id: "email_subscription",
        header: "Email subscription",
        render: (c) =>
          c.accepts_marketing ? (
            <span className="inline-flex items-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
              Subscribed
            </span>
          ) : (
            <span className="text-xs text-slate-400">Not subscribed</span>
          ),
      },
      {
        id: "location",
        header: "Location",
        render: (c) => {
          const a = c.default_address || {};
          const city = (a.city as string) || "";
          const country = (a.country as string) || "";
          return (
            <span className="text-xs text-slate-600">
              {[city, country].filter(Boolean).join(", ") || "—"}
            </span>
          );
        },
      },
      {
        id: "orders",
        header: "Orders",
        sortKey: "orders_count",
        render: (c) => <span className="text-slate-700">{c.orders_count}</span>,
      },
      {
        id: "spent",
        header: "Amount spent",
        sortKey: "total_spent",
        render: (c) => (
          <span className="font-medium text-slate-900">
            {Number(c.total_spent).toFixed(2)} {c.currency}
          </span>
        ),
      },
      {
        id: "last_order",
        header: "Last order",
        render: (c) =>
          c.last_order_at ? (
            <span className="text-xs text-slate-600">
              {c.last_order_name || ""}{" "}
              <span className="text-slate-400">
                · {new Date(c.last_order_at).toLocaleDateString()}
              </span>
            </span>
          ) : (
            <span className="text-xs text-slate-400">—</span>
          ),
      },
      {
        id: "tags",
        header: "Tags",
        render: (c) =>
          c.tags && c.tags.length > 0 ? (
            <div className="flex flex-wrap gap-1 max-w-[180px]">
              {c.tags.slice(0, 2).map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-700"
                >
                  {t}
                </span>
              ))}
              {c.tags.length > 2 && (
                <span className="text-xs text-slate-500">
                  +{c.tags.length - 2}
                </span>
              )}
            </div>
          ) : (
            <span className="text-xs text-slate-400">—</span>
          ),
      },
      {
        id: "source",
        header: "Source",
        render: (c) =>
          c.shopify_customer_id ? (
            <span className="inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
              Shopify
            </span>
          ) : (
            <span className="inline-flex items-center rounded-full bg-slate-100 text-slate-600 ring-1 ring-inset ring-slate-500/20 px-2 py-0.5 text-xs font-medium">
              Manual
            </span>
          ),
      },
    ],
    [],
  );

  const bulkActions = useMemo<BulkAction<Customer>[]>(
    () => [
      {
        id: "add_tag",
        label: "Add tag",
        run: async (selected) => {
          const tag = window.prompt("Tag to add to selected customers:");
          if (!tag) return false;
          await customersApi.bulk(
            selected.map((c) => c.id),
            "add_tag",
            { tag },
          );
          await load();
        },
      },
      {
        id: "remove_tag",
        label: "Remove tag",
        run: async (selected) => {
          const tag = window.prompt("Tag to remove from selected customers:");
          if (!tag) return false;
          await customersApi.bulk(
            selected.map((c) => c.id),
            "remove_tag",
            { tag },
          );
          await load();
        },
      },
      {
        id: "delete",
        label: "Delete",
        destructive: true,
        run: async (selected) => {
          if (
            !window.confirm(
              `Delete ${selected.length} customer(s)? Customers with orders will be skipped.`,
            )
          )
            return false;
          await customersApi.bulk(
            selected.map((c) => c.id),
            "delete",
          );
          await load();
        },
      },
    ],
    [load],
  );

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-end justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Customers</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total} customer{total === 1 ? "" : "s"} · Shopify + manual
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
            placeholder="Search name / email / phone…"
            className="w-72 border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
          />
          <ImportExportBar
            resource="customers"
            exportParams={{
              search: search || undefined,
              sort: sortKey,
              dir: sortDir,
            }}
            onImported={() => load()}
          />
          <Link
            to="/customers/new"
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + New customer
          </Link>
        </div>
      </div>

      <DataTable<Customer>
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
          setParam("sort", s?.key ?? null);
          setParam("dir", s?.dir ?? null);
        }}
        selectable
        bulkActions={bulkActions}
        syncToUrl={false}
      />
    </div>
  );
}
