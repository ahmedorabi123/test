import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { purchaseOrdersApi, type PurchaseOrder } from "../api/purchaseOrders";
import DataTable, {
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

const STATUS_STYLES: Record<string, string> = {
  draft: "bg-gray-100 text-gray-700",
  ordered: "bg-blue-100 text-blue-700",
  partial: "bg-amber-100 text-amber-800",
  received: "bg-emerald-100 text-emerald-700",
  cancelled: "bg-red-100 text-red-700",
};

export default function PurchasesPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const status = searchParams.get("status") || "";
  const search = searchParams.get("search") || "";
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;

  const [rows, setRows] = useState<PurchaseOrder[]>([]);
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
      const { data, meta } = await purchaseOrdersApi.list({
        page,
        per_page: perPage,
        status: status || undefined,
        search: search || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load purchase orders");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, status, search, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<PurchaseOrder>[]>(
    () => [
      {
        id: "po_number",
        header: "PO #",
        sortKey: "po_number",
        render: (po) => (
          <Link
            to={`/purchases/${po.id}`}
            className="font-mono text-xs text-indigo-700 hover:underline"
          >
            {po.po_number}
          </Link>
        ),
      },
      {
        id: "supplier",
        header: "Supplier",
        render: (po) => (
          <span className="text-slate-800">{po.supplier_name || "—"}</span>
        ),
      },
      {
        id: "warehouse",
        header: "Warehouse",
        render: (po) => (
          <span className="text-slate-600">{po.warehouse_name || "—"}</span>
        ),
      },
      {
        id: "status",
        header: "Status",
        sortKey: "status",
        render: (po) => (
          <span
            className={`inline-flex items-center rounded px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[po.status] ?? "bg-slate-100 text-slate-700"}`}
          >
            {po.status}
          </span>
        ),
      },
      {
        id: "expected_at",
        header: "Expected",
        sortKey: "expected_at",
        render: (po) => (
          <span className="text-xs text-slate-500">
            {po.expected_at
              ? new Date(po.expected_at).toLocaleDateString()
              : "—"}
          </span>
        ),
      },
      {
        id: "created_at",
        header: "Created",
        sortKey: "created_at",
        render: (po) => (
          <span className="text-xs text-slate-500">
            {new Date(po.created_at).toLocaleDateString()}
          </span>
        ),
      },
    ],
    [],
  );

  return (
    <PageContainer className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-semibold text-slate-900">
          Purchase Orders
        </h1>
        <Link
          to="/purchases/new"
          className="inline-flex min-h-11 items-center justify-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          + New PO
        </Link>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:items-center">
        <input
          type="text"
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder="Search PO # or supplier…"
          className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-64"
        />
        <select
          value={status}
          onChange={(e) => {
            setParam("page", "1");
            setParam("status", e.target.value);
          }}
          className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-auto"
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="ordered">Ordered</option>
          <option value="partial">Partial</option>
          <option value="received">Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <DataTable<PurchaseOrder>
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
        emptyMessage="No purchase orders yet."
        mobileCardRenderer={(po) => (
          <MobileRowCard
            title={
              <Link
                to={`/purchases/${po.id}`}
                className="font-mono text-sm text-indigo-700 hover:underline"
              >
                {po.po_number}
              </Link>
            }
            subtitle={po.supplier_name}
            meta={`${po.currency} ${Number(po.total).toFixed(2)}`}
            fields={[
              { label: "Warehouse", value: po.warehouse_name || "-" },
              {
                label: "Status",
                value: (
                  <span
                    className={`inline-block rounded px-2 py-0.5 text-xs ${STATUS_STYLES[po.status] ?? "bg-slate-100 text-slate-700"}`}
                  >
                    {po.status}
                  </span>
                ),
              },
              {
                label: "Expected",
                value: po.expected_at
                  ? new Date(po.expected_at).toLocaleDateString()
                  : "-",
              },
            ]}
            actions={
              <Link
                to={`/purchases/${po.id}`}
                className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
              >
                Open purchase
              </Link>
            }
          />
        )}
        syncToUrl={false}
      />
    </PageContainer>
  );
}
