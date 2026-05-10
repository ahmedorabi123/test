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
  stock_items?: Array<{
    id: string;
    warehouse_id: string;
    quantity_on_hand: number;
    quantity_reserved: number;
    quantity_unavailable: number;
    available: number;
    low_stock_threshold: number;
  }>;
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
  const [existingStockItemId, setExistingStockItemId] = useState<string | null>(
    null,
  );
  const [search, setSearch] = useState("");
  const [options, setOptions] = useState<VariantOption[]>([]);
  const [qty, setQty] = useState("0");
  const [threshold, setThreshold] = useState("0");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!warehouseId || variantId) {
      setOptions([]);
      return;
    }
    const query = search.trim();
    const t = setTimeout(async () => {
      try {
        const res = await api.get<{ data: VariantOption[] }>("/variants", {
          params: {
            search: query || undefined,
            per_page: query ? 15 : 25,
            include: "stock_items_summary",
            warehouse_id: warehouseId,
          },
        });
        setOptions(res.data.data);
      } catch {
        setOptions([]);
      }
    }, query ? 250 : 0);
    return () => clearTimeout(t);
  }, [search, variantId, warehouseId]);

  useEffect(() => {
    if (!variantId || !warehouseId) {
      setExistingStockItemId(null);
      return;
    }
    const loadSelectedVariant = async () => {
      try {
        const res = await api.get<{ data: VariantOption[] }>(
          `/variants?ids=${encodeURIComponent(variantId)}&include=stock_items_summary&warehouse_id=${encodeURIComponent(warehouseId)}&per_page=1`,
        );
        const stockItem = res.data.data[0]?.stock_items?.[0];
        setExistingStockItemId(stockItem?.id || null);
        if (stockItem) {
          setQty(String(stockItem.quantity_on_hand));
          setThreshold(String(stockItem.low_stock_threshold || 0));
        } else {
          setQty("0");
          setThreshold("0");
        }
      } catch {
        setExistingStockItemId(null);
      }
    };
    loadSelectedVariant();
  }, [variantId, warehouseId]);

  async function save() {
    if (!variantId || !warehouseId) {
      setError("Pick a variant and a warehouse");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const payload = {
        quantity_on_hand: parseInt(qty || "0", 10),
        low_stock_threshold: parseInt(threshold || "0", 10),
      };
      if (existingStockItemId) {
        await stockItemsApi.update(existingStockItemId, payload);
      } else {
        await stockItemsApi.create({
          variant_id: variantId,
          warehouse_id: warehouseId,
          ...payload,
        });
      }
      onCreated();
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        err.response?.data?.error?.detail || err.message || "Failed to create",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-4">Set stock</h2>
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
              onChange={(e) => {
                setWarehouseId(e.target.value);
                setVariantId("");
                setVariantLabel("");
                setExistingStockItemId(null);
                setSearch("");
                setOptions([]);
                setQty("0");
                setThreshold("0");
              }}
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
            <div className="flex gap-2">
              <input
                type="text"
                value={variantId ? variantLabel : search}
                disabled={!warehouseId}
                placeholder={
                  warehouseId
                    ? "Search by SKU, variant or product title..."
                    : "Choose a warehouse first"
                }
                onChange={(e) => {
                  setVariantId("");
                  setVariantLabel("");
                  setExistingStockItemId(null);
                  setSearch(e.target.value);
                }}
                className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm disabled:bg-slate-50 disabled:text-slate-400"
              />
              {variantId && (
                <button
                  type="button"
                  onClick={() => {
                    setVariantId("");
                    setVariantLabel("");
                    setExistingStockItemId(null);
                    setSearch("");
                  }}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-600"
                >
                  Clear
                </button>
              )}
            </div>
            {options.length > 0 && !variantId && (
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
                      const stockItem = o.stock_items?.[0];
                      setExistingStockItemId(stockItem?.id || null);
                      if (stockItem) {
                        setQty(String(stockItem.quantity_on_hand));
                        setThreshold(
                          String(stockItem.low_stock_threshold || 0),
                        );
                      } else {
                        setQty("0");
                        setThreshold("0");
                      }
                      setSearch("");
                      setOptions([]);
                    }}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="font-medium text-slate-900">
                          {o.product_title} · {o.title}
                        </div>
                        <div className="text-xs text-slate-500 font-mono">
                          {o.sku || "no SKU"}
                        </div>
                      </div>
                      {o.stock_items?.[0] ? (
                        <span className="shrink-0 rounded-md bg-slate-100 px-2 py-1 text-[11px] text-slate-700">
                          {o.stock_items[0].quantity_on_hand} on hand /{" "}
                          {o.stock_items[0].quantity_reserved} reserved
                        </span>
                      ) : (
                        <span className="shrink-0 rounded-md bg-emerald-50 px-2 py-1 text-[11px] text-emerald-700">
                          new in warehouse
                        </span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Quantity on hand
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
            {saving ? "Saving…" : "Save stock"}
          </button>
        </div>
      </div>
    </div>
  );
}

interface AdjustState {
  stockItem: StockItem;
  onHand: string;
  unavailable: string;
  unavailabilityReason: string;
  saving: boolean;
  error: string | null;
}

function AdjustModal({
  state,
  onChange,
  onSave,
  onClose,
}: {
  state: AdjustState;
  onChange: (patch: Partial<AdjustState>) => void;
  onSave: () => void;
  onClose: () => void;
}) {
  const si = state.stockItem;
  const onHand = parseInt(state.onHand || "0", 10) || 0;
  const unavailable = parseInt(state.unavailable || "0", 10) || 0;
  const available = Math.max(onHand - si.quantity_reserved - unavailable, 0);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-md p-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-1">
          Adjust stock
        </h2>
        <p className="text-xs text-slate-500 mb-4">
          {si.product_title} · {si.variant_title} @ {si.warehouse_name}
        </p>
        {state.error && (
          <div className="mb-3 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
            {state.error}
          </div>
        )}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <label className="text-sm font-medium text-slate-700">
              Physical on hand
            </label>
            <input
              type="number"
              min={0}
              value={state.onHand}
              onChange={(e) => onChange({ onHand: e.target.value })}
              className="w-28 border border-slate-300 rounded-lg px-3 py-1.5 text-sm text-right"
            />
          </div>
          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <label className="text-sm font-medium text-slate-700">
                Unavailable
              </label>
              <input
                type="number"
                min={0}
                value={state.unavailable}
                onChange={(e) => onChange({ unavailable: e.target.value })}
                className="w-28 border border-slate-300 rounded-lg px-3 py-1.5 text-sm text-right"
              />
            </div>
            {unavailable > 0 && (
              <input
                type="text"
                placeholder="Reason (e.g. damaged, quality hold)"
                value={state.unavailabilityReason}
                onChange={(e) =>
                  onChange({ unavailabilityReason: e.target.value })
                }
                className="w-full border border-slate-300 rounded-lg px-3 py-1.5 text-sm"
              />
            )}
          </div>
          <div className="flex items-center justify-between text-sm text-slate-500">
            <span title="Reserved stock comes from active order allocations and is not edited manually.">
              Committed (reserved)
            </span>
            <span className="font-mono text-slate-700">
              {si.quantity_reserved}
            </span>
          </div>
          <div className="flex items-center justify-between border-t border-slate-200 pt-3">
            <span className="text-sm font-semibold text-slate-700">
              Available
            </span>
            <span
              className={`text-lg font-bold ${
                available === 0
                  ? "text-red-600"
                  : available <= si.low_stock_threshold
                    ? "text-amber-600"
                    : "text-emerald-600"
              }`}
            >
              {available}
            </span>
          </div>
          <p className="text-[11px] text-slate-400">
            Available = physical on hand - committed - unavailable.
          </p>
        </div>
        <div className="flex items-center justify-end gap-2 mt-5 pt-4 border-t border-slate-200">
          <button
            type="button"
            onClick={onClose}
            className="text-sm text-slate-600 hover:text-slate-900 px-3 py-2"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={state.saving}
            onClick={onSave}
            className="bg-indigo-600 text-white text-sm font-medium px-4 py-2 rounded-lg hover:bg-indigo-700 disabled:opacity-50"
          >
            {state.saving ? "Saving…" : "Save"}
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
  const hasUnavailable = searchParams.get("has_unavailable") === "1";
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

  const [search, setSearch] = useState("");
  const [searchDebounced, setSearchDebounced] = useState("");

  const [modalOpen, setModalOpen] = useState(false);
  const [adjustState, setAdjustState] = useState<AdjustState | null>(null);

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
      })
      .catch(() => setError("Failed to load warehouses"))
      .finally(() => setWarehousesLoaded(true));
  }, []);

  // Debounce search input
  useEffect(() => {
    const t = setTimeout(() => setSearchDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await stockItemsApi.list({
        warehouse_id: warehouseId || undefined,
        low_stock: lowStock || undefined,
        has_unavailable: hasUnavailable || undefined,
        search: searchDebounced || undefined,
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
  }, [
    warehouseId,
    lowStock,
    hasUnavailable,
    searchDebounced,
    page,
    perPage,
    sortKey,
    sortDir,
  ]);

  useEffect(() => {
    load();
  }, [load]);

  const openAdjust = (si: StockItem) => {
    setAdjustState({
      stockItem: si,
      onHand: String(si.quantity_on_hand),
      unavailable: String(si.quantity_unavailable),
      unavailabilityReason: si.unavailability_reason ?? "",
      saving: false,
      error: null,
    });
  };

  const saveAdjust = async () => {
    if (!adjustState) return;
    const { stockItem: si } = adjustState;
    const newOnHand = parseInt(adjustState.onHand, 10);
    const newUnavailable = parseInt(adjustState.unavailable, 10);
    if (
      isNaN(newOnHand) ||
      newOnHand < 0 ||
      isNaN(newUnavailable) ||
      newUnavailable < 0
    ) {
      setAdjustState({
        ...adjustState,
        error: "Quantities must be non-negative numbers",
      });
      return;
    }
    setAdjustState({ ...adjustState, saving: true, error: null });
    try {
      await stockItemsApi.update(si.id, {
        quantity_on_hand: newOnHand,
        quantity_unavailable: newUnavailable,
        unavailability_reason: adjustState.unavailabilityReason || null,
      });
      setAdjustState(null);
      await load();
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setAdjustState({
        ...adjustState,
        saving: false,
        error:
          err.response?.data?.error?.detail || err.message || "Failed to save",
      });
    }
  };

  const columns = useMemo<Column<StockItem>[]>(
    () => [
      {
        id: "product",
        header: "Product",
        sortKey: "product_title",
        render: (si) => (
          <div className="flex flex-col min-w-0">
            <span className="font-medium text-slate-900 truncate">
              {si.product_title ?? "—"}
            </span>
            <span className="text-xs text-slate-500 truncate">
              {si.variant_title ?? "Default"}
            </span>
          </div>
        ),
      },
      {
        id: "sku",
        header: "SKU",
        sortKey: "variant_sku",
        render: (si) => (
          <span className="font-mono text-xs text-slate-600">
            {si.sku ?? "—"}
          </span>
        ),
      },
      {
        id: "warehouse",
        header: "Warehouse",
        sortKey: "warehouse_name",
        render: (si) => (
          <span className="text-sm text-slate-600">
            {si.warehouse_name ?? "—"}
          </span>
        ),
      },
      {
        id: "unavailable",
        header: "Unavailable",
        sortKey: "quantity_unavailable",
        render: (si) =>
          si.quantity_unavailable > 0 ? (
            <span
              title={si.unavailability_reason ?? undefined}
              className="inline-flex items-center rounded-full bg-amber-50 text-amber-700 ring-1 ring-amber-300 px-2 py-0.5 text-xs font-medium"
            >
              {si.quantity_unavailable}
            </span>
          ) : (
            <span className="text-slate-400 text-sm">—</span>
          ),
      },
      {
        id: "committed",
        header: "Committed",
        sortKey: "quantity_reserved",
        render: (si) => (
          <span
            className={`text-sm ${
              si.quantity_reserved > 0
                ? "font-medium text-slate-900"
                : "text-slate-400"
            }`}
          >
            {si.quantity_reserved}
          </span>
        ),
      },
      {
        id: "available",
        header: "Available",
        sortKey: "available",
        render: (si) => (
          <span
            className={`font-semibold text-sm ${
              si.available === 0
                ? "text-red-600"
                : si.low_stock
                  ? "text-amber-600"
                  : "text-emerald-600"
            }`}
          >
            {si.available}
          </span>
        ),
      },
      {
        id: "on_hand",
        header: "On hand",
        sortKey: "quantity_on_hand",
        render: (si) => (
          <span className="text-sm text-slate-700">{si.quantity_on_hand}</span>
        ),
      },
      {
        id: "status",
        header: "Stock",
        sortKey: "available",
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
              openAdjust(si);
            }}
            className="text-xs text-indigo-600 hover:underline whitespace-nowrap"
          >
            Adjust
          </button>
        ),
      },
    ],
    [],
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

  const lowCount = rows.filter((r) => r.low_stock).length;

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Inventory</h1>
          <p className="text-sm text-slate-500 mt-1">
            {total.toLocaleString()} SKUs ·{" "}
            {warehouseId
              ? "Selected warehouse"
              : `All warehouses (${warehouses.length})`}
            {lowCount > 0 && (
              <span className="ml-3 inline-flex items-center gap-1 rounded-full bg-red-50 text-red-700 ring-1 ring-red-200 px-2 py-0.5 text-xs font-medium">
                ⚠ {lowCount} low on this page
              </span>
            )}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <ImportExportBar
            resource="stock_items"
            allowImport={false}
            exportParams={{
              warehouse_id: warehouseId || undefined,
              low_stock: lowStock ? "true" : undefined,
              search: searchDebounced || undefined,
              sort: sortKey,
              dir: sortDir,
            }}
          />
          <button
            onClick={() => setModalOpen(true)}
            className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
          >
            + Set stock
          </button>
          <TransferStockButton warehouses={warehouses} onDone={load} />
          <ShowroomReportButton warehouses={warehouses} onDone={load} />
        </div>
      </div>

      {/* Search + filter bar */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="search"
          placeholder="Search by SKU, product or variant…"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setParam("page", "1");
          }}
          className="w-64 border border-slate-300 rounded-lg px-3 py-2 text-sm"
        />
        <select
          value={warehouseId}
          onChange={(e) => {
            setParam("page", "1");
            setParam("warehouse_id", e.target.value);
          }}
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm"
        >
          {!warehousesLoaded && <option value="">Loading…</option>}
          <option value="">All warehouses</option>
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
        <label className="flex items-center gap-2 text-sm text-slate-600">
          <input
            type="checkbox"
            checked={hasUnavailable}
            onChange={(e) => {
              setParam("page", "1");
              setParam("has_unavailable", e.target.checked ? "1" : null);
            }}
            className="rounded border-slate-300 text-amber-600"
          />
          Has unavailable
        </label>
      </div>

      {adjustState && (
        <AdjustModal
          state={adjustState}
          onChange={(patch) =>
            setAdjustState((s) => (s ? { ...s, ...patch } : s))
          }
          onSave={saveAdjust}
          onClose={() => setAdjustState(null)}
        />
      )}

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
        syncToUrl={false}
      />
    </div>
  );
}
