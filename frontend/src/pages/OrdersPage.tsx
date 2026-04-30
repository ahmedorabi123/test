import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  ordersApi,
  type FinancialStatus,
  type Order,
  type OrderStatus,
} from "../api/orders";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";

const STATUS_STYLES: Record<OrderStatus, string> = {
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  processing: "bg-blue-50 text-blue-700 ring-blue-600/20",
  fulfilled: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  cancelled: "bg-gray-100 text-gray-600 ring-gray-500/20",
  refunded: "bg-rose-50 text-rose-700 ring-rose-600/20",
};

const FIN_STATUS_STYLES: Record<FinancialStatus, string> = {
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  authorized: "bg-sky-50 text-sky-700 ring-sky-600/20",
  paid: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  partially_paid: "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
  refunded: "bg-rose-50 text-rose-700 ring-rose-600/20",
  voided: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

function formatMoney(val: string | number | undefined, currency = "USD") {
  const n = Number(val ?? 0);
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(n);
}

export default function OrdersPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "placed_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const search = searchParams.get("search") || "";
  const status = (searchParams.get("status") || "") as OrderStatus | "";
  const financialStatus = (searchParams.get("financial_status") || "") as
    | FinancialStatus
    | "";
  const source = searchParams.get("source") || "";

  const [rows, setRows] = useState<Order[]>([]);
  const [total, setTotal] = useState(0);
  const [totalValue, setTotalValue] = useState("0");
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
      const res = await ordersApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        status: status || undefined,
        financial_status: financialStatus || undefined,
        source: source || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(res.data);
      setTotal(res.meta.total);
      setTotalValue(res.meta.summary.total_value);
    } catch (e) {
      setError((e as Error).message || "Failed to load orders");
    } finally {
      setLoading(false);
    }
  }, [
    page,
    perPage,
    search,
    status,
    financialStatus,
    source,
    sortKey,
    sortDir,
  ]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Order>[]>(
    () => [
      {
        id: "order_number",
        header: "Order",
        sortKey: "order_number",
        render: (o) => (
          <Link
            to={`/orders/${o.id}`}
            className="font-mono text-indigo-700 hover:underline"
          >
            {o.order_number}
          </Link>
        ),
      },
      {
        id: "placed_at",
        header: "Date",
        sortKey: "placed_at",
        render: (o) => (
          <span className="text-slate-700">
            {new Date(o.placed_at).toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
              hour: "2-digit",
              minute: "2-digit",
            })}
          </span>
        ),
      },
      {
        id: "customer",
        header: "Customer",
        sortKey: "customer_email",
        render: (o) => (
          <div className="flex flex-col">
            <span className="text-slate-900">{o.customer_name || "—"}</span>
            <span className="text-xs text-slate-500">
              {o.customer_email || "—"}
            </span>
          </div>
        ),
      },
      {
        id: "channel",
        header: "Channel",
        render: (o) => (
          <span className="text-xs font-medium capitalize text-slate-600">
            {o.source === "shopify" ? "Online Store" : o.source}
          </span>
        ),
      },
      {
        id: "total",
        header: "Total",
        sortKey: "total_price",
        render: (o) => (
          <span className="font-medium text-slate-900">
            {formatMoney(o.total_price, o.currency)}
          </span>
        ),
      },
      {
        id: "fin_status",
        header: "Payment",
        sortKey: "financial_status",
        render: (o) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${FIN_STATUS_STYLES[o.financial_status]}`}
          >
            {o.financial_status.replace("_", " ")}
          </span>
        ),
      },
      {
        id: "status",
        header: "Fulfillment",
        sortKey: "status",
        render: (o) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[o.status]}`}
          >
            {o.status}
          </span>
        ),
      },
      {
        id: "delivery_status",
        header: "Delivery",
        render: (o) =>
          o.delivery_status ? (
            <span className="text-xs capitalize text-slate-600">
              {o.delivery_status.replace(/_/g, " ")}
            </span>
          ) : (
            <span className="text-xs text-slate-400">—</span>
          ),
      },
      {
        id: "items",
        header: "Items",
        render: (o) => (
          <span className="text-slate-700">{o.items_count ?? 0}</span>
        ),
      },
      {
        id: "delivery_method",
        header: "Delivery method",
        render: (o) => (
          <span className="text-xs text-slate-600 truncate max-w-[180px] block">
            {o.delivery_method || "—"}
          </span>
        ),
      },
      {
        id: "tags",
        header: "Tags",
        render: (o) =>
          o.tags && o.tags.length > 0 ? (
            <div className="flex flex-wrap gap-1 max-w-[220px]">
              {o.tags.slice(0, 3).map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-700"
                >
                  {t}
                </span>
              ))}
              {o.tags.length > 3 && (
                <span className="text-xs text-slate-500">
                  +{o.tags.length - 3}
                </span>
              )}
            </div>
          ) : (
            <span className="text-xs text-slate-400">—</span>
          ),
      },
    ],
    [],
  );

  const bulkActions = useMemo<BulkAction<Order>[]>(
    () => [
      {
        id: "cancel",
        label: "Cancel",
        destructive: true,
        run: async (sel) => {
          if (!window.confirm(`Cancel ${sel.length} order(s)?`)) return false;
          await ordersApi.bulk(
            sel.map((o) => o.id),
            "cancel",
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
          <h1 className="text-2xl font-semibold text-slate-900">Orders</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total · {formatMoney(totalValue)} gross
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
            placeholder="Search #, email, name…"
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
            <option value="pending">Pending</option>
            <option value="processing">Processing</option>
            <option value="fulfilled">Fulfilled</option>
            <option value="cancelled">Cancelled</option>
            <option value="refunded">Refunded</option>
          </select>
          <select
            value={source}
            onChange={(e) => {
              setParam("page", "1");
              setParam("source", e.target.value);
            }}
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
          >
            <option value="">All sources</option>
            <option value="shopify">Shopify</option>
            <option value="manual">Manual</option>
            <option value="showroom">Showroom</option>
          </select>
          <ImportExportBar
            resource="orders"
            allowImport={false}
            exportParams={{
              search: search || undefined,
              status: status || undefined,
              financial_status: financialStatus || undefined,
              source: source || undefined,
              sort: sortKey,
              dir: sortDir,
            }}
          />
          <Link
            to="/orders/new"
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + New order
          </Link>
        </div>
      </div>

      <DataTable<Order>
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
