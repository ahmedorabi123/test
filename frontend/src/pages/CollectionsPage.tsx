import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { collectionsApi, type Collection } from "../api/collections";
import DataTable, {
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

const KIND_STYLES: Record<string, string> = {
  custom: "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
  smart: "bg-purple-50 text-purple-700 ring-purple-600/20",
};

export default function CollectionsPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const search = searchParams.get("search") || "";
  const kindFilter = searchParams.get("kind") || "";

  const [rows, setRows] = useState<Collection[]>([]);
  const [total, setTotal] = useState(0);
  const [kindCounts, setKindCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState(search);
  const debouncedSearch = useDebouncedValue(searchInput, 300);

  // Push debounced typing into the URL (page resets to 1 on change).
  useEffect(() => {
    if (debouncedSearch === search) return;
    const sp = new URLSearchParams(searchParams);
    if (debouncedSearch) sp.set("search", debouncedSearch);
    else sp.delete("search");
    sp.set("page", "1");
    setSearchParams(sp, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch]);

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
      const res = await collectionsApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        kind: (kindFilter as "custom" | "smart" | undefined) || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(res.data);
      setTotal(res.meta.total);
      setKindCounts(res.meta.kind_counts ?? {});
    } catch (e) {
      setError((e as Error).message || "Failed to load collections");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, search, kindFilter, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Collection>[]>(
    () => [
      {
        id: "title",
        header: "Collection",
        sortKey: "title",
        render: (c) => (
          <div className="flex flex-col min-w-0">
            <Link
              to={`/collections/${c.id}`}
              className="font-medium text-indigo-700 hover:underline truncate max-w-[280px]"
            >
              {c.title}
            </Link>
            <span className="text-xs text-slate-500 font-mono truncate max-w-[280px]">
              {c.handle}
            </span>
          </div>
        ),
      },
      {
        id: "kind",
        header: "Products condition",
        sortKey: "kind",
        render: (c) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${KIND_STYLES[c.kind] ?? KIND_STYLES.custom}`}
          >
            {c.kind === "custom"
              ? "Manual"
              : `${c.disjunctive ? "Any" : "All"} rules (${c.rules?.length ?? 0})`}
          </span>
        ),
      },
      {
        id: "products_count",
        header: "Products",
        sortKey: "products_count",
        render: (c) => (
          <span className="text-xs text-slate-600">{c.products_count}</span>
        ),
      },
      {
        id: "source",
        header: "Source",
        sortKey: "source",
        render: (c) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              c.source === "shopify"
                ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
                : "bg-slate-100 text-slate-600 ring-slate-500/20"
            }`}
          >
            {c.source === "shopify" ? "Shopify" : "Manual"}
          </span>
        ),
      },
    ],
    [],
  );

  const visibleKindCount = Object.values(kindCounts).filter(
    (count) => count > 0,
  ).length;
  const showKindFilter = visibleKindCount > 1 || Boolean(kindFilter);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-xl font-semibold text-slate-800 flex-1">
          Collections
        </h1>
        <Link
          to="/collections/new"
          className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700"
        >
          + New Collection
        </Link>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3">
        <input
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder="Search collections…"
          className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 w-56"
        />
        {showKindFilter && (
          <select
            value={kindFilter}
            onChange={(e) => {
              setParam("kind", e.target.value || null);
              setParam("page", "1");
            }}
            className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="">All collections</option>
            {(kindCounts.custom ?? 0) > 0 && (
              <option value="custom">Custom</option>
            )}
            {(kindCounts.smart ?? 0) > 0 && (
              <option value="smart">Smart</option>
            )}
          </select>
        )}
      </div>

      {/* Error */}
      {error && (
        <div className="rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {/* Table */}
      <DataTable
        columns={columns}
        rows={rows}
        loading={loading}
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
        page={page}
        perPage={perPage}
        total={total}
        onPageChange={(p) => setParam("page", String(p))}
        onPerPageChange={(pp) => {
          setParam("per_page", String(pp));
          setParam("page", "1");
        }}
        emptyMessage="No collections found."
        syncToUrl={false}
      />
    </div>
  );
}
