import api from "./client";

export interface Refund {
  id: string;
  order_id: string;
  amount: string;
  currency: string;
  reason: string | null;
  note: string | null;
  processed_at: string | null;
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
  }>;
}

export interface RefundListParams {
  page?: number;
  per_page?: number;
  order_id?: string;
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
    line_items?: Array<{
      order_line_item_id: string;
      quantity: number;
      subtotal?: string;
    }>;
  }) =>
    api
      .post<{ data: Refund }>("/refunds", { refund: payload })
      .then((r) => r.data.data),
};
