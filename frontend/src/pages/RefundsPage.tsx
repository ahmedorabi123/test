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

type RefundDetail = Refund & { journal_entry_id?: string | null };

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
  const reason = searchParams.get("reason") || "";
  const restock = searchParams.get("restock") || "";
  const from = searchParams.get("from") || "";
  const to = searchParams.get("to") || "";

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
        reason: reason || undefined,
        restock: restock ? restock === "true" : undefined,
        from: from || undefined,
        to: to || undefined,
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
  }, [
    page,
    perPage,
    search,
    status,
    kind,
    source,
    reason,
    restock,
    from,
    to,
    sortKey,
    sortDir,
  ]);

  useEffect(() => {
    load();
  }, [load]);

  const applyFilterSet = (values: Record<string, string | null>) => {
    const sp = new URLSearchParams(searchParams);
    Object.entries(values).forEach(([key, value]) => {
      if (!value) sp.delete(key);
      else sp.set(key, value);
    });
    sp.set("page", "1");
    setSearchParams(sp, { replace: true });
  };

  const transitionRefund = useCallback(async (row: Refund, toStatus: string) => {
    try {
      if (toStatus === "cancelled") await refundsApi.cancel(row.id);
      else await refundsApi.transition(row.id, toStatus);
      await load();
    } catch (e) {
      setError((e as Error).message || "Refund transition failed");
    }
  }, [load]);

  const today = new Date().toISOString().slice(0, 10);
  const weekStartDate = new Date();
  weekStartDate.setDate(weekStartDate.getDate() - weekStartDate.getDay());
  const weekStart = weekStartDate.toISOString().slice(0, 10);

  const money = useCallback(
    (row: Refund) => `${Number(row.amount).toFixed(2)} ${row.currency}`,
    [],
  );

  const columns = useMemo<Column<Refund>[]>(
    () => [
      {
        id: "refund",
        header: "Refund #",
        render: (row) => (
          <Link
            to={`/refunds/${row.id}`}
            className="font-mono text-xs font-medium text-indigo-700 hover:underline"
          >
            RF-{row.id.slice(0, 8).toUpperCase()}
          </Link>
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
          <div className="flex flex-col">
            <span className="text-slate-900">
              {row.customer?.name || row.customer?.email || "-"}
            </span>
            {row.customer?.email && (
              <span className="text-xs text-slate-500">{row.customer.email}</span>
            )}
          </div>
        ),
      },
      {
        id: "type",
        header: "Type",
        render: (row) => (
          <span
            className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              row.kind === "exchange"
                ? "bg-indigo-50 text-indigo-700 ring-indigo-600/20"
                : row.full
                  ? "bg-rose-50 text-rose-700 ring-rose-600/20"
                  : "bg-amber-50 text-amber-700 ring-amber-600/20"
            }`}
          >
            {row.kind === "exchange" ? "exchange" : row.full ? "full" : "partial"}
          </span>
        ),
      },
      {
        id: "reason",
        header: "Reason",
        sortKey: "reason",
        render: (row) => <span>{row.reason || "-"}</span>,
      },
      {
        id: "amount",
        header: "Amount",
        sortKey: "amount",
        className: "text-right tabular-nums",
        headerClassName: "text-right",
        render: (row) => <span className="font-medium">{money(row)}</span>,
      },
      {
        id: "restock",
        header: "Restock",
        render: (row) => (
          <span className="text-xs text-slate-700">
            {row.restock
              ? row.inventory_restocked
                ? "Restocked"
                : "Pending"
              : "No"}
          </span>
        ),
      },
      {
        id: "status",
        header: "Status",
        sortKey: "status",
        render: (row) => {
          const value = row.status || "processed";
          const cls =
            value === "processed"
              ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
              : value === "approved"
                ? "bg-sky-50 text-sky-700 ring-sky-600/20"
                : value === "cancelled"
                  ? "bg-gray-100 text-gray-600 ring-gray-500/20"
                  : "bg-amber-50 text-amber-700 ring-amber-600/20";
          return (
            <span
              className={`inline-flex rounded-md px-2 py-0.5 text-xs font-medium capitalize ring-1 ring-inset ${cls}`}
            >
              {value}
            </span>
          );
        },
      },
      {
        id: "processed",
        header: "Processed at",
        sortKey: "processed_at",
        render: (row) => (
          <span className="text-slate-600">
            {row.processed_at
              ? new Date(row.processed_at).toLocaleDateString()
              : "-"}
          </span>
        ),
      },
      {
        id: "actions",
        header: "Actions",
        render: (row) => {
          const value = row.status || "processed";
          const actionable =
            !row.shopify_refund_id && !["processed", "cancelled"].includes(value);
          if (!actionable) return <span className="text-xs text-slate-400">-</span>;
          return (
            <div className="flex flex-wrap gap-1">
              {value === "draft" && (
                <button
                  type="button"
                  onClick={() => transitionRefund(row, "approved")}
                  className="rounded border border-slate-300 px-2 py-1 text-xs text-slate-700 hover:bg-slate-50"
                >
                  Approve
                </button>
              )}
              <button
                type="button"
                onClick={() => transitionRefund(row, "processed")}
                className="rounded bg-indigo-600 px-2 py-1 text-xs text-white hover:bg-indigo-700"
              >
                Process
              </button>
              <button
                type="button"
                onClick={() => transitionRefund(row, "cancelled")}
                className="rounded border border-rose-300 px-2 py-1 text-xs text-rose-700 hover:bg-rose-50"
              >
                Cancel
              </button>
            </div>
          );
        },
      },
    ],
    [money, transitionRefund],
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
            reason,
            restock,
            from,
            to,
            sort: sortKey,
            dir: sortDir,
          }}
        />
        <ManualRefundButton onCreated={load} />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-slate-500 mr-1">Quick filters:</span>
        <RefundsChip
          label="Draft"
          active={status === "draft"}
          onClick={() => {
            setParam("status", status === "draft" ? null : "draft");
            setParam("page", "1");
          }}
        />
        <RefundsChip
          label="Processed"
          active={status === "processed"}
          onClick={() => {
            setParam("status", status === "processed" ? null : "processed");
            setParam("page", "1");
          }}
        />
        <RefundsChip
          label="Manual / Estebdal"
          active={kind === "manual" || kind === "estebdal"}
          onClick={() => {
            const isOn = kind === "manual" || kind === "estebdal";
            setParam("kind", isOn ? null : "manual");
            setParam("page", "1");
          }}
        />
        <RefundsChip
          label="With restock"
          active={restock === "true"}
          onClick={() => {
            setParam("restock", restock === "true" ? null : "true");
            setParam("page", "1");
          }}
        />
        {(status || kind || source || reason || restock || search) && (
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
        <select
          value={restock}
          onChange={(e) => {
            setParam("restock", e.target.value);
            setParam("page", "1");
          }}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">All restock</option>
          <option value="true">Restock</option>
          <option value="false">No restock</option>
        </select>
      </div>

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => applyFilterSet({ from: today, to: null })}
          className="rounded-full border border-slate-300 px-3 py-1 text-xs text-slate-700 hover:bg-slate-50"
        >
          Today
        </button>
        <button
          type="button"
          onClick={() => applyFilterSet({ from: weekStart, to: null })}
          className="rounded-full border border-slate-300 px-3 py-1 text-xs text-slate-700 hover:bg-slate-50"
        >
          This week
        </button>
        <button
          type="button"
          onClick={() => applyFilterSet({ status: "draft" })}
          className="rounded-full border border-amber-300 px-3 py-1 text-xs text-amber-700 hover:bg-amber-50"
        >
          Pending approval
        </button>
        <button
          type="button"
          onClick={() => applyFilterSet({ restock: "true", status: "approved" })}
          className="rounded-full border border-indigo-300 px-3 py-1 text-xs text-indigo-700 hover:bg-indigo-50"
        >
          Restock pending
        </button>
        {(status || kind || source || restock || from || to || reason) && (
          <button
            type="button"
            onClick={() =>
              applyFilterSet({
                status: null,
                kind: null,
                source: null,
                restock: null,
                reason: null,
                from: null,
                to: null,
              })
            }
            className="rounded-full border border-slate-300 px-3 py-1 text-xs text-slate-500 hover:bg-slate-50"
          >
            Clear filters
          </button>
        )}
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
        renderExpanded={(row) => <RefundExpanded refundId={row.id} />}
        syncToUrl={false}
      />
    </div>
  );
}

function RefundExpanded({ refundId }: { refundId: string }) {
  const [refund, setRefund] = useState<RefundDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    refundsApi
      .get(refundId)
      .then((row) => setRefund(row as RefundDetail))
      .catch((e) => setError((e as Error).message || "Failed to load refund"));
  }, [refundId]);

  if (error) return <div className="text-sm text-rose-600">{error}</div>;
  if (!refund) return <div className="text-sm text-slate-400">Loading...</div>;

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_260px]">
      <div className="rounded-lg border border-slate-200 bg-white">
        <div className="border-b border-slate-100 px-3 py-2 text-xs font-semibold uppercase text-slate-500">
          Line items
        </div>
        {(refund.line_items ?? []).length > 0 ? (
          <table className="w-full text-xs">
            <thead className="bg-slate-50 text-slate-500">
              <tr>
                <th className="px-3 py-2 text-left">Item</th>
                <th className="px-3 py-2 text-left">SKU</th>
                <th className="px-3 py-2 text-right">Qty</th>
                <th className="px-3 py-2 text-right">Subtotal</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(refund.line_items ?? []).map((item) => (
                <tr key={item.id}>
                  <td className="px-3 py-2 text-slate-800">
                    {item.title || item.variant_title || "Item"}
                  </td>
                  <td className="px-3 py-2 font-mono text-slate-500">
                    {item.sku || "-"}
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">
                    {item.quantity}
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">
                    {Number(item.subtotal).toFixed(2)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <div className="px-3 py-3 text-sm text-slate-400">
            No line items recorded
          </div>
        )}
      </div>
      <div className="rounded-lg border border-slate-200 bg-white p-3 text-sm">
        <div className="text-xs font-semibold uppercase text-slate-500">
          Accounting
        </div>
        <div className="mt-2 text-xs text-slate-500">Journal entry</div>
        <div className="break-all font-mono text-xs text-slate-800">
          {refund.journal_entry_id || "-"}
        </div>
        {refund.note && (
          <div className="mt-3 whitespace-pre-wrap text-xs text-slate-600">
            {refund.note}
          </div>
        )}
      </div>
    </div>
  );
}

function RefundsChip({
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
      className={`rounded-full border px-3 py-1 text-xs transition ${
        active
          ? "border-indigo-500 bg-indigo-50 text-indigo-700"
          : "border-slate-300 bg-white text-slate-600 hover:bg-slate-50"
      }`}
    >
      {label}
    </button>
  );
}

