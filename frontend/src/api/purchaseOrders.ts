import api from "./client";

export interface PurchaseOrderLineItem {
  id: string;
  purchase_order_id: string;
  variant_id: string | null;
  sku: string | null;
  title: string | null;
  quantity_ordered: number;
  quantity_received: number;
  remaining: number;
  unit_cost: string;
  subtotal: string;
}

export interface PurchaseOrder {
  id: string;
  po_number: string;
  supplier_id: string;
  supplier_name?: string;
  warehouse_id: string | null;
  warehouse_name?: string;
  status: "draft" | "ordered" | "partial" | "received" | "cancelled";
  currency: string;
  subtotal: string;
  total_tax: string;
  total_shipping: string;
  total: string;
  ordered_at?: string | null;
  expected_at?: string | null;
  received_at?: string | null;
  notes?: string | null;
  created_at: string;
  updated_at: string;
  line_items?: PurchaseOrderLineItem[];
}

export type PurchaseOrderUpdatePayload = Omit<
  Partial<PurchaseOrder>,
  "line_items"
> & {
  line_items?: Array<{ id: string; quantity_received: number }>;
};

export interface CreatePOPayload {
  supplier_id: string;
  warehouse_id?: string;
  currency?: string;
  expected_at?: string;
  notes?: string;
  line_items: Array<{
    variant_id?: string;
    sku?: string;
    title?: string;
    quantity_ordered: number;
  }>;
}

export const purchaseOrdersApi = {
  list: (
    params: {
      page?: number;
      per_page?: number;
      status?: string;
      supplier_id?: string;
      search?: string;
      sort?: string;
      dir?: "asc" | "desc";
    } = {},
  ) =>
    api
      .get<{
        data: PurchaseOrder[];
        meta: { page: number; per_page: number; total: number };
      }>("/purchase_orders", { params })
      .then((r) => r.data),
  get: (id: string) =>
    api
      .get<{ data: PurchaseOrder }>(`/purchase_orders/${id}`)
      .then((r) => r.data.data),
  create: (payload: CreatePOPayload) =>
    api
      .post<{
        data: PurchaseOrder;
      }>("/purchase_orders", { purchase_order: payload })
      .then((r) => r.data.data),
  update: (id: string, payload: PurchaseOrderUpdatePayload) =>
    api
      .patch<{
        data: PurchaseOrder;
      }>(`/purchase_orders/${id}`, { purchase_order: payload })
      .then((r) => r.data.data),
  receive: (
    id: string,
    receipts: Array<{ line_item_id: string; quantity: number }>,
    warehouseId?: string,
  ) =>
    api
      .post<{ data: PurchaseOrder }>(`/purchase_orders/${id}/receive`, {
        receipts,
        warehouse_id: warehouseId,
      })
      .then((r) => r.data.data),
  cancel: (id: string) =>
    api
      .post<{ data: PurchaseOrder }>(`/purchase_orders/${id}/cancel`)
      .then((r) => r.data.data),
};
