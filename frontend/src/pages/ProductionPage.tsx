import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  productionOrdersApi,
  variantsApi,
  type ProductionOrder,
  type Variant,
} from "../api/production";
import { warehousesApi, type Warehouse } from "../api/inventory";
import DataTable, {
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import StagesDrawer from "../components/manufacturing/StagesDrawer";

const STATUS_STYLES: Record<string, string> = {
  draft: "bg-gray-100 text-gray-700 ring-gray-500/20",
  in_progress: "bg-sky-50 text-sky-700 ring-sky-600/20",
  completed: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  cancelled: "bg-rose-50 text-rose-700 ring-rose-600/20",
};

export default function ProductionPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "25", 10),
  );
  const sortKey = searchParams.get("sort") || "created_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;
  const status = searchParams.get("status") || "";

  const [rows, setRows] = useState<ProductionOrder[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showModal, setShowModal] = useState(false);
  const [stagesFor, setStagesFor] = useState<string | null>(null);

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
      const res = await productionOrdersApi.list({
        page,
        per_page: perPage,
        status: status || undefined,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(res.data);
      setTotal(res.meta.total);
    } catch (e) {
      setError((e as Error).message || "Failed to load production orders");
    } finally {
      setLoading(false);
    }
  }, [page, perPage, status, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const runOrder = async (po: ProductionOrder) => {
    if (
      !window.confirm(
        `Run production order ${po.number}? This will consume components and produce stock.`,
      )
    )
      return;
    try {
      await productionOrdersApi.run(po.id);
      await load();
    } catch (e) {
      alert((e as Error).message || "Failed to run");
    }
  };

  const cancelOrder = async (po: ProductionOrder) => {
    if (!window.confirm(`Cancel production order ${po.number}?`)) return;
    try {
      await productionOrdersApi.cancel(po.id);
      await load();
    } catch (e) {
      alert((e as Error).message || "Failed to cancel");
    }
  };

  const columns = useMemo<Column<ProductionOrder>[]>(
    () => [
      {
        id: "number",
        header: "Number",
        sortKey: "number",
        render: (po) => (
          <span className="font-medium text-slate-900">{po.number}</span>
        ),
      },
      {
        id: "parent",
        header: "Parent Variant",
        render: (po) =>
          po.parent_variant ? (
            <div>
              <div className="text-slate-900">
                {po.parent_variant.product_title}
              </div>
              <div className="text-xs text-slate-500">
                {po.parent_variant.sku}
                {po.parent_variant.title ? ` · ${po.parent_variant.title}` : ""}
              </div>
            </div>
          ) : (
            "—"
          ),
      },
      {
        id: "warehouse",
        header: "Warehouse",
        render: (po) => po.warehouse_name || "—",
      },
      {
        id: "quantity",
        header: "Qty",
        sortKey: "quantity",
        render: (po) => <span className="tabular-nums">{po.quantity}</span>,
      },
      {
        id: "status",
        header: "Status",
        sortKey: "status",
        render: (po) => (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              STATUS_STYLES[po.status] || STATUS_STYLES.draft
            }`}
          >
            {po.status.replace("_", " ")}
          </span>
        ),
      },
      {
        id: "created_at",
        header: "Created",
        sortKey: "created_at",
        render: (po) => new Date(po.created_at).toLocaleString(),
      },
      {
        id: "actions",
        header: "",
        render: (po) => (
          <div className="flex gap-2">
            <button
              onClick={() => setStagesFor(po.id)}
              className="text-xs bg-slate-100 text-slate-700 ring-1 ring-inset ring-slate-300 px-2 py-1 rounded hover:bg-slate-200"
            >
              Stages
            </button>
            {po.status === "draft" && (
              <button
                onClick={() => runOrder(po)}
                className="text-xs bg-emerald-600 text-white px-2 py-1 rounded hover:bg-emerald-700"
              >
                Run
              </button>
            )}
            {(po.status === "draft" || po.status === "in_progress") && (
              <button
                onClick={() => cancelOrder(po)}
                className="text-xs bg-rose-50 text-rose-700 ring-1 ring-inset ring-rose-600/20 px-2 py-1 rounded hover:bg-rose-100"
              >
                Cancel
              </button>
            )}
          </div>
        ),
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Production</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} production order(s)
          </p>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={status}
            onChange={(e) => {
              setParam("page", "1");
              setParam("status", e.target.value);
            }}
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
          >
            <option value="">All statuses</option>
            <option value="draft">Draft</option>
            <option value="in_progress">In progress</option>
            <option value="completed">Completed</option>
            <option value="cancelled">Cancelled</option>
          </select>
          <button
            onClick={() => setShowModal(true)}
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + New production order
          </button>
        </div>
      </div>

      <DataTable<ProductionOrder>
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
        syncToUrl={false}
      />

      {showModal && (
        <NewProductionOrderModal
          onClose={() => setShowModal(false)}
          onCreated={() => {
            setShowModal(false);
            load();
          }}
        />
      )}

      {stagesFor && (
        <StagesDrawer
          orderId={stagesFor}
          onClose={() => setStagesFor(null)}
          onChanged={load}
        />
      )}

      <div className="text-sm text-slate-500">
        Need to edit a bill of materials?{" "}
        <Link to="/production/bom" className="text-indigo-600 hover:underline">
          Open BOM editor →
        </Link>
      </div>
    </div>
  );
}

function NewProductionOrderModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: () => void;
}) {
  const [variantQuery, setVariantQuery] = useState("");
  const [variantResults, setVariantResults] = useState<Variant[]>([]);
  const [variant, setVariant] = useState<Variant | null>(null);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [warehouseId, setWarehouseId] = useState<string>("");
  const [quantity, setQuantity] = useState<number>(1);
  const [notes, setNotes] = useState<string>("");
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    warehousesApi.list().then((ws) => {
      const own = ws.filter((w) => w.active && (w.kind ?? "own") === "own");
      setWarehouses(own);
      if (own[0]) setWarehouseId(own[0].id);
    });
  }, []);

  useEffect(() => {
    const t = setTimeout(async () => {
      if (variantQuery.trim().length < 2) {
        setVariantResults([]);
        return;
      }
      try {
        const res = await variantsApi.search(variantQuery.trim());
        setVariantResults(res);
      } catch {
        /* ignore */
      }
    }, 250);
    return () => clearTimeout(t);
  }, [variantQuery]);

  const submit = async () => {
    if (!variant || !warehouseId || quantity <= 0) {
      setErr("Select a variant, warehouse, and positive quantity");
      return;
    }
    setSubmitting(true);
    setErr(null);
    try {
      await productionOrdersApi.create({
        parent_variant_id: variant.id,
        warehouse_id: warehouseId,
        quantity,
        notes: notes.trim() || undefined,
      });
      onCreated();
    } catch (e) {
      setErr((e as Error).message || "Failed to create");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4">
        <div className="flex items-start justify-between">
          <h2 className="text-lg font-semibold">New production order</h2>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-700"
          >
            ✕
          </button>
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium text-slate-600">
            Parent variant
          </label>
          {variant ? (
            <div className="flex items-center justify-between border border-slate-300 rounded-lg px-3 py-2 text-sm bg-slate-50">
              <div>
                <div className="font-medium">{variant.product_title}</div>
                <div className="text-xs text-slate-500">
                  {variant.sku}
                  {variant.title ? ` · ${variant.title}` : ""}
                </div>
              </div>
              <button
                onClick={() => setVariant(null)}
                className="text-xs text-rose-600 hover:underline"
              >
                Change
              </button>
            </div>
          ) : (
            <>
              <input
                type="text"
                value={variantQuery}
                onChange={(e) => setVariantQuery(e.target.value)}
                placeholder="Search SKU or product name…"
                className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
              />
              {variantResults.length > 0 && (
                <div className="border border-slate-200 rounded-lg max-h-48 overflow-auto divide-y divide-slate-100">
                  {variantResults.map((v) => (
                    <button
                      key={v.id}
                      onClick={() => {
                        setVariant(v);
                        setVariantQuery("");
                        setVariantResults([]);
                      }}
                      className="w-full text-left px-3 py-2 text-sm hover:bg-slate-50"
                    >
                      <div className="font-medium">{v.product_title}</div>
                      <div className="text-xs text-slate-500">
                        {v.sku}
                        {v.title ? ` · ${v.title}` : ""}
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </>
          )}
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium text-slate-600">
            Warehouse
          </label>
          <select
            value={warehouseId}
            onChange={(e) => setWarehouseId(e.target.value)}
            className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
          >
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name} ({w.code})
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium text-slate-600">Quantity</label>
          <input
            type="number"
            min={1}
            value={quantity}
            onChange={(e) => setQuantity(parseInt(e.target.value || "0", 10))}
            className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
          />
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium text-slate-600">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
          />
        </div>

        {err && <div className="text-sm text-rose-600">{err}</div>}

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-3 py-2 text-sm rounded-lg border border-slate-300 hover:bg-slate-50"
          >
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={submitting}
            className="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-60"
          >
            {submitting ? "Creating…" : "Create"}
          </button>
        </div>
      </div>
    </div>
  );
}
