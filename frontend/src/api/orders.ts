import api from "./client";
import type { Fulfillment } from "./fulfillments";
import type { Refund } from "./refunds";
import type { Warehouse } from "./inventory";

export type OrderStatus =
  | "pending"
  | "processing"
  | "fulfilled"
  | "cancelled"
  | "refunded";

export type FinancialStatus =
  | "pending"
  | "authorized"
  | "paid"
  | "partially_paid"
  | "partially_refunded"
  | "refunded"
  | "voided";

export interface OrderLineItem {
  id: string;
  order_id: string;
  variant_id: string | null;
  sku: string | null;
  title: string;
  variant_title: string | null;
  quantity: number;
  price: string;
  total_discount: string;
  total_tax: string;
  line_total: string;
  fulfilled_quantity?: number;
  reserved_quantity?: number;
}

export interface StockAllocation {
  id: string;
  status: "active" | "released" | "consumed";
  quantity: number;
  note?: string | null;
  stock_item_id: string;
  warehouse_id: string;
  warehouse_name: string | null;
  warehouse_code: string | null;
  on_hand: number;
  reserved: number;
  unavailable: number;
  available: number;
}

export interface OrderStockAllocationLine extends OrderLineItem {
  reserved_quantity: number;
  allocations: StockAllocation[];
}

export interface Order {
  id: string;
  order_number: string;
  external_number: string | null;
  source: "manual" | "shopify" | "showroom";
  status: OrderStatus;
  financial_status: FinancialStatus;
  fulfillment_status: string | null;
  currency: string;
  subtotal_price: string;
  total_tax: string;
  total_shipping: string;
  total_discount: string;
  total_refunded?: string;
  total_price: string;
  customer_email: string | null;
  customer_name: string | null;
  shipping_address?: Record<string, unknown>;
  billing_address?: Record<string, unknown>;
  notes?: string | null;
  placed_at: string;
  cancelled_at: string | null;
  shopify_order_id: number | null;
  read_only_origin?: boolean;
  tags?: string[];
  delivery_method?: string | null;
  delivery_status?: string | null;
  items_count?: number;
  payment_gateway_names?: string[];
  risk_level?: string | null;
  cancel_reason?: string | null;
  closed_at?: string | null;
  total_outstanding?: string;
  shopify_order_status_url?: string | null;
  created_at: string;
  updated_at: string;
  line_items?: OrderLineItem[];
  fulfillments?: Fulfillment[];
  refunds?: Refund[];
  customer_id?: string | null;
  location_id?: number | null;
}

export interface WarehouseAvailability {
  stock_item_id: string;
  warehouse_id: string;
  warehouse_name?: string | null;
  available: number;
  on_hand: number;
  reserved: number;
  unavailable: number;
}

export interface OrderListMeta {
  page: number;
  per_page: number;
  total: number;
  summary: {
    total_count: number;
    total_value: string;
  };
}

export interface OrderListParams {
  page?: number;
  per_page?: number;
  search?: string;
  status?: OrderStatus | "";
  financial_status?: FinancialStatus | "";
  source?: string;
  delivery_status?: string;
  from?: string;
  to?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export interface OrderStats {
  window_days: number;
  count: number;
  total_revenue: string;
  by_status: Partial<Record<OrderStatus, number>>;
  pending_count: number;
}

export const ordersApi = {
  list: (params: OrderListParams = {}) =>
    api
      .get<{ data: Order[]; meta: OrderListMeta }>("/orders", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api.get<{ data: Order }>(`/orders/${id}`).then((r) => r.data.data),

  stats: (window = 30) =>
    api
      .get<{ data: OrderStats }>("/orders/stats", { params: { window } })
      .then((r) => r.data.data),

  create: (payload: {
    source?: "manual" | "showroom";
    currency?: string;
    customer_id?: string | null;
    customer_email?: string;
    customer_name?: string;
    notes?: string;
    total_shipping?: string;
    mark_paid?: boolean;
    warehouse_id?: string;
    location_id?: number;
    shipping_address?: Record<string, unknown>;
    billing_address?: Record<string, unknown>;
    line_items: Array<{
      variant_id?: string;
      sku?: string;
      title?: string;
      variant_title?: string;
      quantity: number;
      price: string;
      total_tax?: string;
      total_discount?: string;
    }>;
  }) =>
    api
      .post<{ data: Order }>("/orders", { order: payload })
      .then((r) => r.data.data),

  bulk: (ids: string[], action_type: "cancel") =>
    api
      .post<{ data: { action: string; affected: number } }>("/orders/bulk", {
        ids,
        action_type,
      })
      .then((r) => r.data.data),

  transition: (id: string, to: string) =>
    api
      .post<{ data: Order }>(`/orders/${id}/transition`, { to })
      .then((r) => r.data.data),

  previewWarehouse: (variantIds: string[]) =>
    api
      .get<{
        data: {
          warehouse: Warehouse | null;
          availability: Record<string, WarehouseAvailability[]>;
        };
      }>("/orders/preview_warehouse", {
        params: { variant_ids: variantIds },
      })
      .then((r) => r.data.data),

  stockAllocation: (id: string) =>
    api
      .get<{
        data: OrderStockAllocationLine[];
      }>(`/orders/${id}/stock_allocation`)
      .then((r) => r.data.data),

  timeline: (id: string) =>
    api
      .get<{
        data: OrderTimelineEntry[];
      }>(`/orders/${id}/timeline`)
      .then((r) => r.data.data),
};

export interface OrderTimelineEntry {
  kind: string;
  type: string;
  occurred_at: string | null;
  payload: Record<string, unknown>;
}
