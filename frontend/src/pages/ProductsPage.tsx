import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { productsApi, type Product } from "../api/products";
import ProductFormModal from "../components/products/ProductFormModal";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";

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

  const [modal, setModal] = useState<"new" | string | null>(null);

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
        render: (p) => (
          <span className="text-xs text-slate-600">
            {p.variants_count ?? 0} variant
            {(p.variants_count ?? 0) === 1 ? "" : "s"}
          </span>
        ),
      },
      {
        id: "type",
        header: "Type",
        render: (p) => (
          <span className="text-xs text-slate-600">
            {p.product_type || "—"}
          </span>
        ),
      },
      {
        id: "vendor",
        header: "Vendor",
        sortKey: "vendor",
        render: (p) => (
          <span className="text-xs text-slate-600">{p.vendor || "—"}</span>
        ),
      },
      {
        id: "tags",
        header: "Tags",
        render: (p) =>
          p.tags && p.tags.length > 0 ? (
            <div className="flex flex-wrap gap-1 max-w-[200px]">
              {p.tags.slice(0, 2).map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-700"
                >
                  {t}
                </span>
              ))}
              {p.tags.length > 2 && (
                <span className="text-xs text-slate-500">
                  +{p.tags.length - 2}
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
        render: (p) =>
          p.shopify_product_id ? (
            <span className="inline-flex items-center rounded-md bg-green-50 text-green-700 ring-1 ring-inset ring-green-600/20 px-2 py-0.5 text-xs font-medium">
              Shopify
            </span>
          ) : (
            <span className="text-slate-400 text-xs">Local</span>
          ),
      },
      {
        id: "updated",
        header: "Updated",
        sortKey: "updated_at",
        render: (p) => (
          <span className="text-xs text-slate-600">
            {new Date(p.updated_at).toLocaleDateString()}
          </span>
        ),
      },
      {
        id: "actions",
        header: "",
        render: (p) => (
          <button
            onClick={(e) => {
              e.stopPropagation();
              setModal(p.id);
            }}
            className="rounded-md bg-white border border-slate-200 px-2.5 py-1 text-xs font-medium text-slate-700 hover:bg-indigo-50 hover:border-indigo-300 hover:text-indigo-700 transition"
          >
            Edit
          </button>
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
    <div className="space-y-6 p-6 max-w-7xl mx-auto">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Products</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total · Shopify + manual
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
            placeholder="Search title / handle…"
            className="w-64 border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
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
          <button
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
            onClick={() => setModal("new")}
          >
            + New product
          </button>
        </div>
      </div>

      {modal !== null && (
        <ProductFormModal
          productId={modal === "new" ? undefined : modal}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            load();
          }}
        />
      )}

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
