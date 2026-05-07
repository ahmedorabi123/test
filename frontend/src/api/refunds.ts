import api from "./client";

export interface Refund {
  id: string;
  order_id: string;
  order?: {
    id: string;
    order_number: string;
    total_price: string;
    total_refunded?: string;
    currency: string;
    status: string;
    financial_status: string;
  } | null;
  customer?: {
    id?: string | null;
    name?: string | null;
    email?: string | null;
    phone?: string | null;
  } | null;
  amount: string;
  currency: string;
  reason: string | null;
  note: string | null;
  status?: "draft" | "approved" | "processed" | "cancelled";
  kind?: "shopify" | "manual" | "estebdal" | "exchange";
  content_hash?: string | null;
  processed_at: string | null;
  restock: boolean;
  inventory_restocked: boolean;
  shopify_refund_id: number | null;
  partial: boolean;
  full: boolean;
  created_at: string;
  updated_at: string;
  line_items?: Array<{
    id: string;
    refund_id: string;
    order_line_item_id: string | null;
    quantity: number;
    subtotal: string;
    restock_type: string | null;
    restock: boolean;
    title?: string | null;
    sku?: string | null;
    variant_title?: string | null;
  }>;
}

export interface RefundListParams {
  page?: number;
  per_page?: number;
  order_id?: string;
  search?: string;
  status?: string;
  kind?: string;
  source?: string;
  reason?: string;
  restock?: boolean;
  from?: string;
  to?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export const refundsApi = {
  list: (params: RefundListParams = {}) =>
    api
      .get<{
        data: Refund[];
        meta: { page: number; per_page: number; total: number };
      }>("/refunds", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api.get<{ data: Refund }>(`/refunds/${id}`).then((r) => r.data.data),

  create: (payload: {
    order_id: string;
    amount: string;
    currency?: string;
    reason?: string;
    note?: string;
    restock?: boolean;
    restock_warehouse_id?: string;
    status?: string;
    kind?: string;
    idempotency_key?: string;
    line_items?: Array<{
      order_line_item_id: string;
      quantity: number;
      subtotal?: string;
    }>;
  }) => {
    const { idempotency_key, ...body } = payload;
    return api
      .post<{ data: Refund }>(
        "/refunds",
        { refund: body },
        idempotency_key
          ? { headers: { "Idempotency-Key": idempotency_key } }
          : undefined,
      )
      .then((r) => r.data.data);
  },

  transition: (id: string, to: string) =>
    api
      .post<{ data: Refund }>(`/refunds/${id}/transition`, { to })
      .then((r) => r.data.data),

  cancel: (id: string) =>
    api.post<{ data: Refund }>(`/refunds/${id}/cancel`).then((r) => r.data.data),
};
