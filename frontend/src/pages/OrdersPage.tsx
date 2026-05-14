import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  ordersApi,
  type FinancialStatus,
  type Order,
  type OrderStatus,
} from "../api/orders";
import { warehousesApi, type Warehouse } from "../api/inventory";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { PageContainer } from "../components/ui/PageContainer";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

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
  partially_refunded: "bg-purple-50 text-purple-700 ring-purple-600/20",
  refunded: "bg-rose-50 text-rose-700 ring-rose-600/20",
  voided: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

const DELIVERY_STATUS_STYLES: Record<string, string> = {
  delivered: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  in_transit: "bg-sky-50 text-sky-700 ring-sky-600/20",
  out_for_delivery: "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  failed: "bg-rose-50 text-rose-700 ring-rose-600/20",
  returned: "bg-purple-50 text-purple-700 ring-purple-600/20",
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
  const deliveryStatus = searchParams.get("delivery_status") || "";
  const warehouseId = searchParams.get("warehouse_id") || "";

  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  useEffect(() => {
    warehousesApi
      .list()
      .then((w) => setWarehouses(w))
      .catch(() => undefined);
  }, []);

  const [rows, setRows] = useState<Order[]>([]);
  const [total, setTotal] = useState(0);
  const [totalValue, setTotalValue] = useState("0");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState(search);
  const debouncedSearch = useDebouncedValue(searchInput, 300);
  const [importMode, setImportMode] = useState<"shopify" | "showroom">(
    "shopify",
  );

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
      const res = await ordersApi.list({
        page,
        per_page: perPage,
        search: search || undefined,
        status: status || undefined,
        financial_status: financialStatus || undefined,
        source: source || undefined,
        delivery_status: deliveryStatus || undefined,
        warehouse_id: warehouseId || undefined,
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
    deliveryStatus,
    warehouseId,
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
        id: "items",
        header: "Items",
        sortKey: "items_count",
        render: (o) => (
          <span className="text-slate-700">{o.items_count ?? 0}</span>
        ),
      },
      {
        id: "delivery_status",
        header: "Delivery",
        sortKey: "delivery_status",
        render: (o) => {
          const ds = o.delivery_status;
          if (!ds) return <span className="text-xs text-slate-400">—</span>;
          const cls =
            DELIVERY_STATUS_STYLES[ds] ??
            "bg-slate-50 text-slate-700 ring-slate-600/20";
          return (
            <span
              className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${cls}`}
            >
              {ds.replace(/_/g, " ")}
            </span>
          );
        },
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
        render: (o) => {
          const tags = o.tags ?? [];
          if (tags.length === 0)
            return <span className="text-xs text-slate-400">—</span>;
          const visible = tags.slice(0, 3);
          const extra = tags.length - visible.length;
          return (
            <div className="flex flex-wrap gap-1 max-w-[220px]">
              {visible.map((t) => (
                <span
                  key={t}
                  className="inline-flex items-center rounded bg-slate-100 px-1.5 py-0.5 text-[11px] text-slate-700"
                >
                  {t}
                </span>
              ))}
              {extra > 0 && (
                <span className="text-[11px] text-slate-500">+{extra}</span>
              )}
            </div>
          );
        },
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
          if (sel.some((order) => order.read_only_origin)) {
            window.alert(
              "Shopify-managed orders cannot be cancelled in the ERP.",
            );
            return false;
          }
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
    <PageContainer className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Orders</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} total · {formatMoney(totalValue)} gross
          </p>
        </div>
        <div className="grid w-full grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:w-auto lg:flex-wrap lg:items-center lg:justify-end">
          <input
            type="text"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search #, email, name…"
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
            className="min-h-11 rounded-lg border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">All sources</option>
            <option value="shopify">Shopify</option>
            <option value="manual">Manual</option>
            <option value="showroom">Showroom</option>
          </select>
          <select
            value={warehouseId}
            onChange={(e) => {
              setParam("page", "1");
              setParam("warehouse_id", e.target.value);
            }}
            className="min-h-11 rounded-lg border border-slate-300 px-3 py-2 text-sm"
            data-testid="orders-warehouse-filter"
          >
            <option value="">All warehouses</option>
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </select>
          <ImportExportBar
            resource="orders"
            allowImport={true}
            importParams={{ mode: importMode }}
            importAccept=".csv,text/csv,.xlsx,.xls"
            importHelpText={
              importMode === "showroom"
                ? "Showroom sales CSV/XLSX. Required headers: Order #, SKU, Quantity, Price. Optional: Customer Email, Customer Name, Warehouse Code, Notes. Each unique 'Order #' becomes one EGP-priced, paid showroom order via the standard manual order pipeline (reservations + accounting included)."
                : "Shopify orders CSV/XLSX. Column headers should match the Shopify export format. The system will validate every row before committing."
            }
            onImported={() => load()}
            exportParams={{
              search: search || undefined,
              status: status || undefined,
              financial_status: financialStatus || undefined,
              source: source || undefined,
              sort: sortKey,
              dir: sortDir,
            }}
          />
          <select
            value={importMode}
            onChange={(e) =>
              setImportMode(e.target.value as "shopify" | "showroom")
            }
            title="Import mode"
            className="min-h-11 rounded-lg border border-slate-300 px-2 py-2 text-xs"
          >
            <option value="shopify">Import as: Shopify export</option>
            <option value="showroom">Import as: Showroom sales</option>
          </select>
          <Link
            to="/orders/new"
            className="inline-flex min-h-11 items-center justify-center gap-1 rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
          >
            + New order
          </Link>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-slate-500 mr-1">Quick filters:</span>
        <OrdersChip
          label="Pending"
          active={status === "pending"}
          onClick={() => {
            setParam("page", "1");
            setParam("status", status === "pending" ? null : "pending");
          }}
        />
        <OrdersChip
          label="In transit"
          active={deliveryStatus === "in_transit"}
          onClick={() => {
            setParam("page", "1");
            setParam(
              "delivery_status",
              deliveryStatus === "in_transit" ? null : "in_transit",
            );
          }}
        />
        <OrdersChip
          label="Delivered"
          active={deliveryStatus === "delivered"}
          onClick={() => {
            setParam("page", "1");
            setParam(
              "delivery_status",
              deliveryStatus === "delivered" ? null : "delivered",
            );
          }}
        />
        <OrdersChip
          label="Refunded"
          active={status === "refunded"}
          onClick={() => {
            setParam("page", "1");
            setParam("status", status === "refunded" ? null : "refunded");
          }}
        />
        {(status || deliveryStatus || financialStatus || source || search) && (
          <button
            onClick={() => {
              const sp = new URLSearchParams();
              setSearchParams(sp, { replace: true });
              setSearchInput("");
            }}
            className="text-xs text-slate-500 hover:text-slate-700 underline ml-2"
          >
            Clear filters
          </button>
        )}
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
        mobileCardRenderer={(order, context) => {
          const delivery = order.delivery_status;
          return (
            <MobileRowCard
              title={
                <Link
                  to={`/orders/${order.id}`}
                  className="font-mono text-indigo-700 hover:underline"
                >
                  {order.order_number}
                </Link>
              }
              subtitle={
                order.customer_name || order.customer_email || "No customer"
              }
              meta={formatMoney(order.total_price, order.currency)}
              selectedControl={
                <input
                  type="checkbox"
                  checked={context.checked}
                  onChange={context.toggleSelected}
                  onClick={(event) => event.stopPropagation()}
                  className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                  aria-label={`Select order ${order.order_number}`}
                />
              }
              fields={[
                {
                  label: "Payment",
                  value: (
                    <span
                      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${FIN_STATUS_STYLES[order.financial_status]}`}
                    >
                      {order.financial_status.replace("_", " ")}
                    </span>
                  ),
                },
                {
                  label: "Fulfillment",
                  value: (
                    <span
                      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[order.status]}`}
                    >
                      {order.status}
                    </span>
                  ),
                },
                {
                  label: "Delivery",
                  value: delivery ? (
                    <span
                      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${DELIVERY_STATUS_STYLES[delivery] ?? "bg-slate-50 text-slate-700 ring-slate-600/20"}`}
                    >
                      {delivery.replace(/_/g, " ")}
                    </span>
                  ) : (
                    "-"
                  ),
                },
                {
                  label: "Date",
                  value: new Date(order.placed_at).toLocaleDateString(),
                },
                { label: "Items", value: order.items_count ?? 0 },
                {
                  label: "Channel",
                  value:
                    order.source === "shopify" ? "Online Store" : order.source,
                },
              ]}
              actions={
                <Link
                  to={`/orders/${order.id}`}
                  className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
                >
                  Open order
                </Link>
              }
            />
          );
        }}
        syncToUrl={false}
      />
    </PageContainer>
  );
}

function OrdersChip({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset ${
        active
          ? "bg-indigo-600 text-white ring-indigo-600"
          : "bg-white text-slate-700 ring-slate-300 hover:bg-slate-50"
      }`}
    >
      {label}
    </button>
  );
}
