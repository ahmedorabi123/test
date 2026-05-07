import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { refundsApi, type Refund } from "../api/refunds";
import ManualRefundButton from "../components/refunds/ManualRefundButton";
import DataTable, {
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

export default function RefundsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const search = searchParams.get("search") || "";
  const status = searchParams.get("status") || "";
  const kind = searchParams.get("kind") || "";
  const source = searchParams.get("source") || "";

  const [searchInput, setSearchInput] = useState(search);
  const debouncedSearch = useDebouncedValue(searchInput, 300);
  const [rows, setRows] = useState<Refund[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (!value) sp.delete(key);
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
      const { data, meta } = await refundsApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        status: status || undefined,
        kind: kind || undefined,
        source: source || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load refunds");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, search, status, kind, source, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Refund>[]>(
    () => [
      {
        id: "amount",
        header: "Amount",
        sortKey: "amount",
        render: (row) => (
          <Link
            to={`/refunds/${row.id}`}
            className="font-medium text-indigo-700 hover:underline"
          >
            {Number(row.amount).toFixed(2)} {row.currency}
          </Link>
        ),
      },
      {
        id: "type",
        header: "Type",
        render: (row) => (
          <span
            className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${row.full ? "bg-rose-50 text-rose-700 ring-rose-600/20" : "bg-amber-50 text-amber-700 ring-amber-600/20"}`}
          >
            {row.full ? "full" : "partial"}
          </span>
        ),
      },
      {
        id: "status",
        header: "Status",
        sortKey: "status",
        render: (row) => (
          <span className="capitalize text-slate-700">
            {row.status || "processed"}
          </span>
        ),
      },
      {
        id: "kind",
        header: "Source",
        sortKey: "kind",
        render: (row) => (
          <span className="capitalize text-slate-700">
            {row.kind || (row.shopify_refund_id ? "shopify" : "manual")}
          </span>
        ),
      },
      {
        id: "order",
        header: "Order",
        sortKey: "order_number",
        render: (row) =>
          row.order ? (
            <Link
              to={`/orders/${row.order.id}`}
              className="font-mono text-indigo-700 hover:underline"
            >
              {row.order.order_number}
            </Link>
          ) : (
            <span className="font-mono text-xs text-slate-500">
              {row.order_id.slice(0, 8)}
            </span>
          ),
      },
      {
        id: "customer",
        header: "Customer",
        sortKey: "customer_name",
        render: (row) => (
          <span>{row.customer?.name || row.customer?.email || "-"}</span>
        ),
      },
      {
        id: "reason",
        header: "Reason",
        sortKey: "reason",
        render: (row) => <span>{row.reason || "-"}</span>,
      },
      {
        id: "processed",
        header: "Processed",
        sortKey: "processed_at",
        render: (row) => (
          <span className="text-slate-600">
            {row.processed_at
              ? new Date(row.processed_at).toLocaleDateString()
              : "-"}
          </span>
        ),
      },
    ],
    [],
  );

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex-1">
          <h1 className="text-2xl font-semibold text-slate-900">Refunds</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} refund records
          </p>
        </div>
        <ImportExportBar
          resource="refunds"
          allowImport={false}
          exportParams={{
            search,
            status,
            kind,
            source,
            sort: sortKey,
            dir: sortDir,
          }}
        />
        <ManualRefundButton onCreated={load} />
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <input
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder="Search order, customer, reason..."
          className="w-72 rounded-lg border border-slate-300 px-3 py-2 text-sm"
        />
        <select
          value={status}
          onChange={(e) => {
            setParam("status", e.target.value);
            setParam("page", "1");
          }}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="approved">Approved</option>
          <option value="processed">Processed</option>
          <option value="cancelled">Cancelled</option>
        </select>
        <select
          value={kind}
          onChange={(e) => {
            setParam("kind", e.target.value);
            setParam("page", "1");
          }}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">All kinds</option>
          <option value="shopify">Shopify</option>
          <option value="manual">Manual</option>
          <option value="estebdal">Estebdal</option>
          <option value="exchange">Exchange</option>
        </select>
        <select
          value={source}
          onChange={(e) => {
            setParam("source", e.target.value);
            setParam("page", "1");
          }}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">All sources</option>
          <option value="shopify">Shopify-linked</option>
          <option value="manual">Manual</option>
          <option value="estebdal">Estebdal</option>
        </select>
      </div>

      <DataTable
        rows={rows}
        columns={columns}
        loading={loading}
        error={error}
        emptyMessage="No refunds found."
        total={total}
        page={page}
        perPage={perPage}
        onPageChange={(p) => setParam("page", String(p))}
        onPerPageChange={(pp) => {
          setParam("per_page", String(pp));
          setParam("page", "1");
        }}
        sort={{ key: sortKey, dir: sortDir }}
        onSortChange={(next) => {
          const sp = new URLSearchParams(searchParams);
          sp.set("sort", next.key);
          sp.set("dir", next.dir);
          sp.set("page", "1");
          setSearchParams(sp, { replace: true });
        }}
        syncToUrl={false}
      />
    </div>
  );
}
