import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { productsApi, type Product } from "../api/products";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

const STATUS_STYLES: Record<string, string> = {
  active: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  draft: "bg-amber-50 text-amber-700 ring-amber-600/20",
  archived: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "updated_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const search = searchParams.get("search") || "";
  const status = searchParams.get("status") || "";

  const [rows, setRows] = useState<Product[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState(search);
  const debouncedSearch = useDebouncedValue(searchInput, 300);

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
      const res = await productsApi.list({
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
      setError((e as Error).message || "Failed to load products");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, search, status, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Product>[]>(
    () => [
      {
        id: "title",
        header: "Product",
        sortKey: "title",
        render: (p) => (
          <div className="flex items-center gap-3">
            {p.images && p.images[0]?.src ? (
              <img
                src={p.images[0].src}
                alt={p.images[0].alt || p.title}
                className="h-10 w-10 rounded object-cover ring-1 ring-slate-200"
              />
            ) : (
              <div className="h-10 w-10 rounded bg-slate-100 ring-1 ring-slate-200 flex items-center justify-center text-slate-400 text-xs">
                IMG
              </div>
            )}
            <div className="flex flex-col min-w-0">
              <Link
                to={`/products/${p.id}`}
                className="font-medium text-indigo-700 hover:underline truncate max-w-[260px]"
              >
                {p.title}
              </Link>
              <span className="text-xs text-slate-500 font-mono truncate max-w-[260px]">
                {p.handle}
              </span>
            </div>
          </div>
        ),
      },
      {
        id: "status",
        header: "Status",
        sortKey: "status",
        render: (p) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[p.status] ?? STATUS_STYLES.draft}`}
          >
            {p.status}
          </span>
        ),
      },
      {
        id: "inventory",
        header: "Inventory",
        sortKey: "inventory_total",
        render: (p) => (
          <span className="text-xs text-slate-600">
            {p.inventory_total ?? 0} in stock
            {" · "}
            {p.variants_count ?? 0} variant
            {(p.variants_count ?? 0) === 1 ? "" : "s"}
          </span>
        ),
      },
      {
        id: "source",
        header: "Source",
        sortKey: "source",
        render: (p) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              p.source === "shopify"
                ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
                : "bg-slate-100 text-slate-600 ring-slate-500/20"
            }`}
          >
            {p.source === "shopify" ? "Shopify" : "Manual"}
          </span>
        ),
      },
      {
        id: "category",
        header: "Category",
        sortKey: "product_type",
        render: (p) => (
          <span className="text-xs text-slate-600">
            {p.primary_category || p.product_type || "—"}
          </span>
        ),
      },
    ],
    [],
  );

  const bulkActions = useMemo<BulkAction<Product>[]>(
    () => [
      {
        id: "activate",
        label: "Activate",
        run: async (sel) => {
          await productsApi.bulk(
            sel.map((p) => p.id),
            "activate",
          );
          await load();
        },
      },
      {
        id: "archive",
        label: "Archive",
        run: async (sel) => {
          await productsApi.bulk(
            sel.map((p) => p.id),
            "archive",
          );
          await load();
        },
      },
      {
        id: "delete",
        label: "Delete",
        destructive: true,
        run: async (sel) => {
          if (!window.confirm(`Delete ${sel.length} product(s)?`)) return false;
          await productsApi.bulk(
            sel.map((p) => p.id),
            "delete",
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
          <h1 className="text-2xl font-semibold text-slate-900">Products</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total · Shopify + manual
          </p>
        </div>
        <div className="grid w-full grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:w-auto lg:flex-wrap lg:items-center lg:justify-end">
          <input
            type="text"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search title / handle…"
            className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500 lg:w-64"
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
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
          </select>
          <ImportExportBar
            resource="products"
            exportParams={{
              search: search || undefined,
              status: status || undefined,
              sort: sortKey,
              dir: sortDir,
            }}
            onImported={() => load()}
          />
          <Link
            to="/products/new"
            className="inline-flex min-h-11 items-center justify-center gap-1 rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
          >
            + New product
          </Link>
        </div>
      </div>

      <DataTable<Product>
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
        mobileCardRenderer={(product, context) => (
          <MobileRowCard
            title={
              <Link
                to={`/products/${product.id}`}
                className="font-medium text-indigo-700 hover:underline"
              >
                {product.title}
              </Link>
            }
            subtitle={product.handle}
            meta={
              <span
                className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[product.status] ?? STATUS_STYLES.draft}`}
              >
                {product.status}
              </span>
            }
            selectedControl={
              <input
                type="checkbox"
                checked={context.checked}
                onChange={context.toggleSelected}
                onClick={(event) => event.stopPropagation()}
                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                aria-label={`Select product ${product.title}`}
              />
            }
            fields={[
              {
                label: "Inventory",
                value: `${product.inventory_total ?? 0} in stock`,
              },
              { label: "Variants", value: product.variants_count ?? 0 },
              {
                label: "Category",
                value: product.primary_category || product.product_type || "-",
              },
              {
                label: "Source",
                value: product.source === "shopify" ? "Shopify" : "Manual",
              },
            ]}
            actions={
              <Link
                to={`/products/${product.id}`}
                className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
              >
                Open product
              </Link>
            }
          />
        )}
        syncToUrl={false}
      />
    </PageContainer>
  );
}
