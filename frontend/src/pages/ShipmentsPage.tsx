import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { fulfillmentsApi, type Fulfillment } from "../api/fulfillments";
import DataTable, { type Column, type SortDir } from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";

const STATUS_STYLES: Record<string, string> = {
  success: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  open: "bg-blue-50 text-blue-700 ring-blue-600/20",
  pending: "bg-amber-50 text-amber-700 ring-amber-600/20",
  cancelled: "bg-gray-100 text-gray-600 ring-gray-500/20",
  error: "bg-rose-50 text-rose-700 ring-rose-600/20",
  failure: "bg-rose-50 text-rose-700 ring-rose-600/20",
};

function StatusBadge({ value }: { value?: string | null }) {
  if (!value) return <span className="text-xs text-slate-400">-</span>;
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[value] || "bg-slate-100 text-slate-600 ring-slate-500/20"}`}>
      {value.replace(/_/g, " ")}
    </span>
  );
}

export default function ShipmentsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(5, parseInt(searchParams.get("per_page") || "25", 10));
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const carrier = searchParams.get("carrier") || "";
  const status = searchParams.get("status") || "";
  const deliveryStatus = searchParams.get("delivery_status") || "";
  const source = searchParams.get("source") || "";
  const search = searchParams.get("search") || "";

  const [searchInput, setSearchInput] = useState(search);
  const [rows, setRows] = useState<Fulfillment[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (!value) sp.delete(key);
    else sp.set(key, value);
    setSearchParams(sp, { replace: true });
  };

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, meta } = await fulfillmentsApi.list({
        page,
        per_page: perPage,
        carrier: carrier || undefined,
        status: status || undefined,
        delivery_status: deliveryStatus || undefined,
        source: source || undefined,
        search: search || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(data);
      setTotal(meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load shipments");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, carrier, status, deliveryStatus, source, search, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const columns = useMemo<Column<Fulfillment>[]>(
    () => [
      {
        id: "tracking_number",
        header: "Tracking",
        sortKey: "tracking_number",
        render: (row) => (
          <Link to={`/shipments/${row.id}`} className="font-mono text-indigo-700 hover:underline">
            {row.tracking_number || row.id.slice(0, 8)}
          </Link>
        ),
      },
      {
        id: "carrier",
        header: "Carrier",
        sortKey: "tracking_company",
        render: (row) => <span className="capitalize text-slate-700">{row.carrier || row.tracking_company || "-"}</span>,
      },
      { id: "status", header: "Status", sortKey: "status", render: (row) => <StatusBadge value={row.status} /> },
      { id: "delivery", header: "Delivery", sortKey: "delivery_status", render: (row) => <StatusBadge value={row.delivery_status} /> },
      {
        id: "order",
        header: "Order",
        sortKey: "order_number",
        render: (row) => row.order ? <Link to={`/orders/${row.order.id}`} className="font-mono text-indigo-700 hover:underline">{row.order.order_number}</Link> : <span className="font-mono text-xs text-slate-500">{row.order_id.slice(0, 8)}</span>,
      },
      {
        id: "customer",
        header: "Customer",
        sortKey: "customer_name",
        render: (row) => <span className="text-slate-700">{row.customer?.name || row.customer?.email || "-"}</span>,
      },
      {
        id: "shipped_at",
        header: "Shipped",
        sortKey: "shipped_at",
        render: (row) => <span className="text-slate-600">{row.shipped_at ? new Date(row.shipped_at).toLocaleDateString() : "-"}</span>,
      },
      {
        id: "delivered_at",
        header: "Delivered",
        sortKey: "delivered_at",
        render: (row) => <span className="text-slate-600">{row.delivered_at ? new Date(row.delivered_at).toLocaleDateString() : "-"}</span>,
      },
    ],
    [],
  );

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex-1">
          <h1 className="text-2xl font-semibold text-slate-900">Shipments</h1>
          <p className="text-sm text-slate-500 mt-1">{total.toLocaleString()} fulfillment records</p>
        </div>
        <ImportExportBar resource="fulfillments" allowImport={false} exportParams={{ carrier, status, delivery_status: deliveryStatus, source, search, sort: sortKey, dir: sortDir }} />
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <input
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              setParam("search", searchInput);
              setParam("page", "1");
            }
          }}
          placeholder="Search tracking, order, customer..."
          className="w-72 rounded-lg border border-slate-300 px-3 py-2 text-sm"
        />
        <select value={carrier} onChange={(e) => { setParam("carrier", e.target.value); setParam("page", "1"); }} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
          <option value="">All carriers</option>
          <option value="bosta">Bosta</option>
          <option value="dhl">DHL</option>
          <option value="ups">UPS</option>
          <option value="aramex">Aramex</option>
        </select>
        <select value={status} onChange={(e) => { setParam("status", e.target.value); setParam("page", "1"); }} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
          <option value="">All statuses</option>
          {Object.keys(STATUS_STYLES).map((value) => <option key={value} value={value}>{value}</option>)}
        </select>
        <select value={source} onChange={(e) => { setParam("source", e.target.value); setParam("page", "1"); }} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
          <option value="">All sources</option>
          <option value="shopify">Shopify</option>
          <option value="manual">Manual</option>
          <option value="bosta">Bosta</option>
        </select>
        <input value={deliveryStatus} onChange={(e) => { setParam("delivery_status", e.target.value); setParam("page", "1"); }} placeholder="Delivery status" className="w-40 rounded-lg border border-slate-300 px-3 py-2 text-sm" />
      </div>

      <DataTable
        rows={rows}
        columns={columns}
        loading={loading}
        error={error}
        emptyMessage="No shipments found."
        total={total}
        page={page}
        perPage={perPage}
        onPageChange={(p) => setParam("page", String(p))}
        onPerPageChange={(pp) => { setParam("per_page", String(pp)); setParam("page", "1"); }}
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
