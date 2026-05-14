import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams, Link } from "react-router-dom";
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
import { RecentWarehouseOrders } from "../components/orders/RecentWarehouseOrders";
import DataTable, {
  type BulkAction,
  type Column,
  type SortDir,
} from "../components/table/DataTable";
import ImportExportBar from "../components/table/ImportExportBar";
import { MobileRowCard } from "../components/table/MobileRowCard";
import { Modal } from "../components/ui/Modal";
import { PageContainer } from "../components/ui/PageContainer";

interface VariantOption {
  id: string;
  sku: string | null;
  title: string;
  product_title: string | null;
  price: string;
  shopify_variant_id?: number | null;
  read_only_origin?: boolean;
  product_source?: "manual" | "shopify";
  product_shopify_product_id?: number | null;
  product_read_only_origin?: boolean;
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

function isStockItemReadOnly(stockItem: StockItem) {
  return Boolean(stockItem.read_only_origin);
}

function isWarehouseMutable(warehouse: Warehouse) {
  return Boolean(
    warehouse.active &&
      !warehouse.read_only_origin &&
      !warehouse.shopify_location_id,
  );
}

function isVariantMutable(variant: VariantOption) {
  return !(
    variant.read_only_origin ||
    variant.shopify_variant_id ||
    variant.product_read_only_origin ||
    variant.product_source === "shopify" ||
    variant.product_shopify_product_id
  );
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
  const eligibleWarehouses = warehouses.filter(isWarehouseMutable);

  useEffect(() => {
    if (!warehouseId || variantId) {
      setOptions([]);
      return;
    }
    const query = search.trim();
    const t = setTimeout(
      async () => {
        try {
          const res = await api.get<{ data: VariantOption[] }>("/variants", {
            params: {
              search: query || undefined,
              per_page: query ? 15 : 25,
              include: "stock_items_summary",
              warehouse_id: warehouseId,
            },
          });
          setOptions(res.data.data.filter(isVariantMutable));
        } catch {
          setOptions([]);
        }
      },
      query ? 250 : 0,
    );
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
    if (!eligibleWarehouses.some((warehouse) => warehouse.id === warehouseId)) {
      setError("Shopify-managed warehouses cannot be edited in the ERP");
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
    <Modal open onClose={onClose} size="md" title="Set stock">
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
            className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
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
            {eligibleWarehouses.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name} ({w.code})
              </option>
            ))}
          </select>
          {eligibleWarehouses.length === 0 && (
            <p className="mt-1 text-xs text-amber-700">
              No editable warehouses are available.
            </p>
          )}
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
              className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-50 disabled:text-slate-400"
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
                className="min-h-11 rounded-lg border border-slate-300 px-3 text-sm text-slate-600"
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
                      setThreshold(String(stockItem.low_stock_threshold || 0));
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

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Quantity on hand
            </label>
            <input
              type="number"
              min={0}
              value={qty}
              onChange={(e) => setQty(e.target.value)}
              className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
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
              className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
        </div>
      </div>

      <div className="mt-6 flex flex-col-reverse gap-2 border-t border-slate-200 pt-4 sm:flex-row sm:items-center sm:justify-end">
        <button
          type="button"
          onClick={onClose}
          className="min-h-11 px-3 text-sm text-slate-600 hover:text-slate-900"
        >
          Cancel
        </button>
        <button
          type="button"
          disabled={saving}
          onClick={save}
          className="min-h-11 rounded-lg bg-indigo-600 px-4 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {saving ? "Saving…" : "Save stock"}
        </button>
      </div>
    </Modal>
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
    <Modal
      open
      onClose={onClose}
      size="sm"
      title="Adjust stock"
      description={`${si.product_title} · ${si.variant_title} @ ${si.warehouse_name}`}
    >
      {state.error && (
        <div className="mb-3 bg-rose-50 border border-rose-200 text-rose-700 px-3 py-2 rounded-md text-sm">
          {state.error}
        </div>
      )}
      <div className="space-y-3">
        <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
          <label className="text-sm font-medium text-slate-700">
            Physical on hand
          </label>
          <input
            type="number"
            min={0}
            value={state.onHand}
            onChange={(e) => onChange({ onHand: e.target.value })}
            className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm text-right sm:w-28"
          />
        </div>
        <div className="space-y-1">
          <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <label className="text-sm font-medium text-slate-700">
              Unavailable
            </label>
            <input
              type="number"
              min={0}
              value={state.unavailable}
              onChange={(e) => onChange({ unavailable: e.target.value })}
              className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm text-right sm:w-28"
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
              className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
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
      <div className="mt-5 flex flex-col-reverse gap-2 border-t border-slate-200 pt-4 sm:flex-row sm:items-center sm:justify-end">
        <button
          type="button"
          onClick={onClose}
          className="min-h-11 px-3 text-sm text-slate-600 hover:text-slate-900"
        >
          Cancel
        </button>
        <button
          type="button"
          disabled={state.saving}
          onClick={onSave}
          className="min-h-11 rounded-lg bg-indigo-600 px-4 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
        >
          {state.saving ? "Saving…" : "Save"}
        </button>
      </div>
    </Modal>
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
    if (isStockItemReadOnly(si)) return;
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
          <div className="flex flex-col min-w-0 gap-1">
            <span className="font-medium text-slate-900 truncate">
              {si.product_title ?? "—"}
            </span>
            <span className="text-xs text-slate-500 truncate">
              {si.variant_title ?? "Default"}
            </span>
            {isStockItemReadOnly(si) && (
              <span className="w-fit rounded bg-emerald-50 px-1.5 py-0.5 text-[11px] font-medium text-emerald-700 ring-1 ring-emerald-200">
                Shopify-managed
              </span>
            )}
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
        render: (si) =>
          isStockItemReadOnly(si) ? (
            <span className="text-xs text-slate-400">Read-only</span>
          ) : (
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
          if (sel.some(isStockItemReadOnly)) {
            window.alert(
              "Shopify-managed inventory rows cannot be modified in the ERP.",
            );
            return false;
          }
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
          if (sel.some(isStockItemReadOnly)) {
            window.alert(
              "Shopify-managed inventory rows cannot be deleted in the ERP.",
            );
            return false;
          }
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
  const selectedWarehouse = warehouses.find((w) => w.id === warehouseId);

  return (
    <PageContainer className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
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
        <div className="flex flex-col gap-2 xs:flex-row xs:flex-wrap xl:justify-end">
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
            className="inline-flex min-h-11 items-center justify-center gap-1 rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
          >
            + Set stock
          </button>
          <TransferStockButton warehouses={warehouses} onDone={load} />
          <Link
            to="/inventory/transfers"
            className="inline-flex min-h-11 items-center justify-center gap-1 rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
          >
            Transfer history
          </Link>
          <ShowroomReportButton warehouses={warehouses} onDone={load} />
        </div>
      </div>

      {/* Search + filter bar */}
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:flex lg:flex-wrap lg:items-center">
        <input
          type="search"
          placeholder="Search by SKU, product or variant…"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setParam("page", "1");
          }}
          className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm lg:w-64"
        />
        <select
          value={warehouseId}
          onChange={(e) => {
            setParam("page", "1");
            setParam("warehouse_id", e.target.value);
          }}
          className="min-h-11 rounded-lg border border-slate-300 px-3 py-2 text-sm"
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

      {warehouseId && (
        <RecentWarehouseOrders
          warehouseId={warehouseId}
          warehouseName={selectedWarehouse?.name}
        />
      )}

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
          defaultWarehouseId={
            warehouses.find(
              (warehouse) =>
                warehouse.id === warehouseId && isWarehouseMutable(warehouse),
            )
              ? warehouseId
              : null
          }
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
        mobileCardRenderer={(stockItem, context) => (
          <MobileRowCard
            title={stockItem.product_title ?? "Unknown product"}
            subtitle={stockItem.variant_title ?? stockItem.sku ?? "Default"}
            meta={
              <span
                className={`font-semibold ${
                  stockItem.available === 0
                    ? "text-red-600"
                    : stockItem.low_stock
                      ? "text-amber-600"
                      : "text-emerald-600"
                }`}
              >
                {stockItem.available} available
              </span>
            }
            selectedControl={
              <input
                type="checkbox"
                checked={context.checked}
                onChange={context.toggleSelected}
                onClick={(event) => event.stopPropagation()}
                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                aria-label={`Select stock item ${stockItem.sku || stockItem.id}`}
              />
            }
            fields={[
              { label: "SKU", value: stockItem.sku || "-" },
              { label: "Warehouse", value: stockItem.warehouse_name || "-" },
              { label: "On hand", value: stockItem.quantity_on_hand },
              { label: "Committed", value: stockItem.quantity_reserved },
              {
                label: "Unavailable",
                value: stockItem.quantity_unavailable || "-",
              },
              { label: "Stock", value: stockItem.low_stock ? "Low" : "OK" },
            ]}
            actions={
              isStockItemReadOnly(stockItem) ? (
                <span className="inline-flex min-h-10 items-center rounded-md bg-emerald-50 px-3 text-sm font-medium text-emerald-700 ring-1 ring-emerald-200">
                  Shopify-managed
                </span>
              ) : (
                <button
                  onClick={() => openAdjust(stockItem)}
                  className="inline-flex min-h-10 items-center justify-center rounded-md border border-slate-300 bg-white px-3 text-sm font-medium text-slate-800 hover:bg-slate-50"
                >
                  Adjust stock
                </button>
              )
            }
          />
        )}
        syncToUrl={false}
      />
    </PageContainer>
  );
}
