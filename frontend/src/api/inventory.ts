import api from "./client";

// ─── Warehouse ───────────────────────────────────────────────────────────────

export interface Warehouse {
  id: string;
  name: string;
  code: string;
  kind?: "own" | "consignment" | "transit";
  partner_name?: string | null;
  partner_email?: string | null;
  partner_phone?: string | null;
  commission_rate?: string | number | null;
  currency?: string | null;
  notes?: string | null;
  shopify_location_id?: number | null;
  read_only_origin?: boolean;
  address: string | null;
  active: boolean;
  created_at: string;
  updated_at: string;
  stock_items?: StockItem[];
}

// ─── Stock Item ───────────────────────────────────────────────────────────────

export interface StockItem {
  id: string;
  variant_id: string;
  warehouse_id: string;
  sku?: string | null;
  variant_title?: string | null;
  product_title?: string | null;
  warehouse_name?: string | null;
  quantity_on_hand: number;
  quantity_reserved: number;
  quantity_unavailable: number;
  unavailability_reason?: string | null;
  available: number;
  low_stock_threshold: number;
  low_stock: boolean;
  read_only_origin?: boolean;
  updated_at: string;
}

export interface StockItemFilters {
  warehouse_id?: string;
  variant_id?: string;
  low_stock?: boolean;
  has_unavailable?: boolean;
  search?: string;
  page?: number;
  per_page?: number;
  sort?: string;
  dir?: "asc" | "desc";
}

// ─── API calls ───────────────────────────────────────────────────────────────

export const warehousesApi = {
  list: () =>
    api.get<{ data: Warehouse[] }>("/warehouses").then((r) => r.data.data),
  get: (id: string) =>
    api.get<{ data: Warehouse }>(`/warehouses/${id}`).then((r) => r.data.data),
  create: (payload: Partial<Warehouse>) =>
    api
      .post<{ data: Warehouse }>("/warehouses", { warehouse: payload })
      .then((r) => r.data.data),
  update: (id: string, payload: Partial<Warehouse>) =>
    api
      .patch<{ data: Warehouse }>(`/warehouses/${id}`, { warehouse: payload })
      .then((r) => r.data.data),
  destroy: (id: string) =>
    api.delete(`/warehouses/${id}`).then(() => undefined),
};

export const stockItemsApi = {
  list: (filters: StockItemFilters = {}) =>
    api
      .get<{
        data: StockItem[];
        meta?: { page: number; per_page: number; total: number };
      }>("/stock_items", { params: filters })
      .then((r) => r.data),
  create: (payload: {
    variant_id: string;
    warehouse_id: string;
    quantity_on_hand?: number;
    low_stock_threshold?: number;
  }) =>
    api
      .post<{ data: StockItem }>("/stock_items", payload)
      .then((r) => r.data.data),
  update: (
    id: string,
    payload: {
      quantity_on_hand?: number;
      low_stock_threshold?: number;
      quantity_unavailable?: number;
      unavailability_reason?: string | null;
    },
  ) =>
    api
      .patch<{ data: StockItem }>(`/stock_items/${id}`, { stock_item: payload })
      .then((r) => r.data.data),
  destroy: (id: string) =>
    api.delete(`/stock_items/${id}`).then(() => undefined),
  bulk: (
    ids: string[],
    action_type: "set_threshold" | "delete",
    payload?: Record<string, unknown>,
  ) =>
    api
      .post<{
        data: { action: string; affected: number };
      }>("/stock_items/bulk", { ids, action_type, payload })
      .then((r) => r.data.data),
};

export const stockTransfersApi = {
  create: (payload: {
    variant_id: string;
    from_warehouse_id: string;
    to_warehouse_id: string;
    quantity: number;
    reason?: string;
  }) =>
    api
      .post<{
        data: {
          from: { warehouse_code: string; on_hand: number };
          to: { warehouse_code: string; on_hand: number };
        };
      }>("/stock_transfers", payload)
      .then((r) => r.data.data),
};

export const showroomSalesApi = {
  create: (payload: {
    warehouse_id: string;
    period: string;
    report_date?: string;
    currency?: string;
    notes?: string;
    line_items: Array<{
      variant_id: string;
      quantity: number;
      unit_price: string;
    }>;
  }) =>
    api
      .post<{
        data: { id: string; order_number: string; total_price: string };
      }>("/showroom_sales", payload)
      .then((r) => r.data.data),
};
