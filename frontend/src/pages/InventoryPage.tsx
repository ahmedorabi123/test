import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import api from "../api/client";
import {
  stockItemsApi,
  warehousesApi,
  type StockItem,
  type Warehouse,
} from "../api/inventory";
import {
  ShopifyBackfillButton,
  TransferStockButton,
  ShowroomReportButton,
} from "../components/inventory/InventoryActions";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";

interface VariantOption {
  id: string;
  sku: string | null;
  title: string;
  product_title: string | null;
  price: string;
}

function NewStockItemModal({
  warehouses,
  defaultWarehouseId,
  onClose,
  onCreated,
}: {
  warehouses: Warehouse[];
  defaultWarehouseId?: string | null;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [warehouseId, setWarehouseId] = useState(defaultWarehouseId || "");
  const [variantId, setVariantId] = useState("");
  const [variantLabel, setVariantLabel] = useState("");
  const [search, setSearch] = useState("");
  const [options, setOptions] = useState<VariantOption[]>([]);
  const [qty, setQty] = useState("0");
  const [threshold, setThreshold] = useState("0");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!search) {
      setOptions([]);
      return;
    }
    const t = setTimeout(async () => {
      try {
        const res = await api.get<{ data: VariantOption[] }>(
          `/variants?search=${encodeURIComponent(search)}&per_page=15`,
        );
        setOptions(res.data.data);
      } catch {
        setOptions([]);
      }
    }, 250);
    return () => clearTimeout(t);
  }, [search]);

  async function save() {
    if (!variantId || !warehouseId) {
      setError("Pick a variant and a warehouse");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await stockItemsApi.create({
        variant_id: variantId,
        warehouse_id: warehouseId,
        quantity_on_hand: parseInt(qty || "0", 10),
        low_stock_threshold: parseInt(threshold || "0", 10),
      });
      onCreated();
    } catch (e: any) {
      setError(
        e?.response?.data?.error?.detail || e?.message || "Failed to create",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-4">
          New stock item
        </h2>
        {error && (
          <div className="mb-3 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
            {error}
          </div>
        )}
        <div className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Warehouse
            </label>
            <select
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
              value={warehouseId}
              onChange={(e) => setWarehouseId(e.target.value)}
            >
              <option value="">Choose warehouse…</option>
              {warehouses.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.name} ({w.code})
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Variant
            </label>
            <input
              type="text"
              value={variantId ? variantLabel : search}
              placeholder="Search by SKU, variant or product title…"
              onChange={(e) => {
                setVariantId("");
                setVariantLabel("");
                setSearch(e.target.value);
              }}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
            {!variantId && options.length > 0 && (
              <ul className="mt-1 max-h-48 overflow-y-auto border border-slate-200 rounded-lg bg-white shadow-sm divide-y divide-slate-100">
                {options.map((o) => (
                  <li
                    key={o.id}
                    className="px-3 py-2 hover:bg-indigo-50 cursor-pointer text-sm"
                    onClick={() => {
                      setVariantId(o.id);
                      setVariantLabel(
                        `${o.product_title ?? ""} · ${o.title}${o.sku ? ` (${o.sku})` : ""}`,
                      );
                      setSearch("");
                      setOptions([]);
                    }}
                  >
                    <div className="font-medium text-slate-900">
                      {o.product_title} · {o.title}
                    </div>
                    <div className="text-xs text-slate-500 font-mono">
                      {o.sku || "no SKU"}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Initial quantity
              </label>
              <input
                type="number"
                min={0}
                value={qty}
                onChange={(e) => setQty(e.target.value)}
                className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Low-stock threshold
              </label>
              <input
                type="number"
                min={0}
                value={threshold}
                onChange={(e) => setThreshold(e.target.value)}
                className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
              />
            </div>
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 mt-6 pt-4 border-t border-slate-200">
          <button
            type="button"
            onClick={onClose}
            className="text-sm text-slate-600 hover:text-slate-900 px-3 py-2"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={saving}
            onClick={save}
            className="bg-indigo-600 text-white text-sm font-medium px-4 py-2 rounded-lg hover:bg-indigo-700 disabled:opacity-50"
          >
            {saving ? "Saving…" : "Create stock item"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function InventoryPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [warehousesLoaded, setWarehousesLoaded] = useState(false);

  const warehouseId = searchParams.get("warehouse_id") || "";
  const lowStock = searchParams.get("low_stock") === "1";
  const page = Math.max(1, parseInt(searchParams.get("page") || "1", 10));
  const perPage = Math.max(
    5,
    parseInt(searchParams.get("per_page") || "50", 10),
  );
  const sortKey = searchParams.get("sort") || "updated_at";
  const sortDir = (searchParams.get("dir") || "desc") as SortDir;

  const [rows, setRows] = useState<StockItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<StockItem | null>(null);
  const [editQty, setEditQty] = useState("");

  const setParam = (key: string, value: string | null) => {
    const sp = new URLSearchParams(searchParams);
    if (value == null || value === "") sp.delete(key);
    else sp.set(key, value);
    setSearchParams(sp, { replace: true });
  };

  useEffect(() => {
    warehousesApi
      .list()
      .then((data) => {
        setWarehouses(data);
        if (!warehouseId && data.length > 0) {
          setParam("warehouse_id", data[0].id);
        }
      })
      .catch(() => setError("Failed to load warehouses"))
      .finally(() => setWarehousesLoaded(true));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const load = useCallback(async () => {
    if (!warehouseId) return;
    setLoading(true);
    setError(null);
    try {
      const res = await stockItemsApi.list({
        warehouse_id: warehouseId,
        low_stock: lowStock || undefined,
        page,
        per_page: perPage,
        sort: sortKey,
        dir: sortDir,
      });
      setRows(res.data);
      setTotal(res.meta?.total ?? res.data.length);
    } catch (e) {
      setError((e as Error).message || "Failed to load stock items");
    } finally {
      setLoading(false);
    }
  }, [warehouseId, lowStock, page, perPage, sortKey, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const saveQty = async (id: string) => {
    const parsed = parseInt(editQty, 10);
    if (isNaN(parsed) || parsed < 0) return;
    try {
      await stockItemsApi.update(id, { quantity_on_hand: parsed });
      setEditing(null);
      setEditQty("");
      await load();
    } catch {
      setError("Failed to update");
    }
  };

  const columns = useMemo<Column<StockItem>[]>(
    () => [
      {
        id: "sku",
        header: "SKU / Product",
        render: (si) => (
          <div className="flex flex-col">
            <span className="font-medium text-slate-900">
              {si.product_title ?? "—"} · {si.variant_title ?? "—"}
            </span>
            <span className="text-xs text-slate-500 font-mono">
              {si.sku ?? "no SKU"}
            </span>
          </div>
        ),
      },
      {
        id: "on_hand",
        header: "On hand",
        sortKey: "quantity_on_hand",
        render: (si) =>
          editing?.id === si.id ? (
            <div className="flex items-center gap-2">
              <input
                type="number"
                min={0}
                value={editQty}
                onChange={(e) => setEditQty(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") saveQty(si.id);
                  if (e.key === "Escape") {
                    setEditing(null);
                    setEditQty("");
                  }
                }}
                onClick={(e) => e.stopPropagation()}
                className="w-20 rounded-md border border-slate-300 px-2 py-1 text-sm text-right"
                autoFocus
              />
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  saveQty(si.id);
                }}
                className="rounded-md bg-indigo-600 px-2 py-1 text-xs text-white hover:bg-indigo-500"
              >
                Save
              </button>
            </div>
          ) : (
            <span className="font-medium text-slate-900">
              {si.quantity_on_hand}
            </span>
          ),
      },
      {
        id: "reserved",
        header: "Reserved",
        render: (si) => si.quantity_reserved,
      },
      {
        id: "available",
        header: "Available",
        render: (si) => <span className="font-semibold">{si.available}</span>,
      },
      {
        id: "threshold",
        header: "Low threshold",
        sortKey: "low_stock_threshold",
        render: (si) => si.low_stock_threshold,
      },
      {
        id: "status",
        header: "Status",
        render: (si) =>
          si.low_stock ? (
            <span className="inline-flex items-center rounded-full bg-red-50 text-red-700 ring-1 ring-red-200 px-2 py-0.5 text-xs font-medium">
              Low
            </span>
          ) : (
            <span className="inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200 px-2 py-0.5 text-xs font-medium">
              OK
            </span>
          ),
      },
      {
        id: "actions",
        header: "",
        render: (si) => (
          <button
            onClick={(e) => {
              e.stopPropagation();
              setEditing(si);
              setEditQty(String(si.quantity_on_hand));
            }}
            className="text-xs text-indigo-600 hover:underline"
          >
            Adjust
          </button>
        ),
      },
    ],
    [editing, editQty],
  );

  const bulkActions = useMemo<BulkAction<StockItem>[]>(
    () => [
      {
        id: "set_threshold",
        label: "Set low-stock threshold",
        run: async (sel) => {
          const t = window.prompt("New low-stock threshold:");
          if (t == null) return false;
          const threshold = parseInt(t, 10);
          if (isNaN(threshold) || threshold < 0) return false;
          await stockItemsApi.bulk(
            sel.map((s) => s.id),
            "set_threshold",
            { threshold },
          );
          await load();
        },
      },
      {
        id: "delete",
        label: "Delete",
        destructive: true,
        run: async (sel) => {
          if (!window.confirm(`Delete ${sel.length} stock item(s)?`))
            return false;
          await stockItemsApi.bulk(
            sel.map((s) => s.id),
            "delete",
          );
          await load();
        },
      },
    ],
    [load],
  );

  const activeWh = warehouses.find((w) => w.id === warehouseId);
  const lowCount = rows.filter((r) => r.low_stock).length;

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Inventory</h1>
          <p className="text-sm text-slate-500 mt-1">
            {activeWh ? `${activeWh.name} (${activeWh.code})` : "—"} ·{" "}
            {total.toLocaleString()} SKUs
            {lowCount > 0 && (
              <span className="ml-3 inline-flex items-center gap-1 rounded-full bg-red-50 text-red-700 ring-1 ring-red-200 px-2 py-0.5 text-xs font-medium">
                ⚠ {lowCount} low on this page
              </span>
            )}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={warehouseId}
            onChange={(e) => {
              setParam("page", "1");
              setParam("warehouse_id", e.target.value);
            }}
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
          >
            {!warehousesLoaded && <option value="">Loading…</option>}
            {warehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name} ({w.code})
              </option>
            ))}
          </select>
          <label className="flex items-center gap-2 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={lowStock}
              onChange={(e) => {
                setParam("page", "1");
                setParam("low_stock", e.target.checked ? "1" : null);
              }}
              className="rounded border-slate-300 text-indigo-600"
            />
            Low stock only
          </label>
          <ImportExportBar
            resource="stock_items"
            allowImport={false}
            exportParams={{
              warehouse_id: warehouseId || undefined,
              low_stock: lowStock ? "true" : undefined,
              sort: sortKey,
              dir: sortDir,
            }}
          />
          <button
            onClick={() => setModalOpen(true)}
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + New stock item
          </button>
          <ShopifyBackfillButton onDone={load} />
          <TransferStockButton warehouses={warehouses} onDone={load} />
          <ShowroomReportButton warehouses={warehouses} onDone={load} />
        </div>
      </div>

      {modalOpen && (
        <NewStockItemModal
          warehouses={warehouses}
          defaultWarehouseId={warehouseId}
          onClose={() => setModalOpen(false)}
          onCreated={() => {
            setModalOpen(false);
            load();
          }}
        />
      )}

      <DataTable<StockItem>
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
