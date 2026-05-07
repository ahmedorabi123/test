import api from "./client";

export interface CustomerAddress {
  id?: number | string;
  address1?: string;
  address2?: string;
  city?: string;
  province?: string;
  province_code?: string;
  country?: string;
  country_code?: string;
  zip?: string;
  phone?: string;
  company?: string;
  first_name?: string;
  last_name?: string;
  name?: string;
  default?: boolean;
}

export interface CustomerOrderSummary {
  id: string;
  order_number: string;
  total_price: string;
  status: string;
  financial_status: string;
  fulfillment_status?: string | null;
  placed_at: string;
  currency?: string;
  shipping_address?: Record<string, string | undefined>;
  line_items?: Array<{
    id: string;
    title: string;
    variant_title?: string | null;
    sku?: string | null;
    quantity: number;
    price: string;
    line_total: string;
  }>;
}

export interface Customer {
  id: string;
  email: string | null;
  phone: string | null;
  first_name: string | null;
  last_name: string | null;
  display_name: string;
  tags: string[];
  default_address: CustomerAddress;
  addresses?: CustomerAddress[];
  accepts_marketing?: boolean;
  verified_email?: boolean;
  tax_exempt?: boolean;
  state?: string | null;
  note?: string | null;
  last_order_id?: number | null;
  last_order_name?: string | null;
  last_order_at?: string | null;
  last_order?: CustomerOrderSummary | null;
  orders_count: number;
  total_spent: string;
  currency: string;
  source: "manual" | "shopify";
  shopify_customer_id: string | null;
  created_at: string;
  updated_at: string;
  orders?: Array<{
    id: string;
    order_number: string;
    total_price: string;
    status: string;
    financial_status: string;
    placed_at: string;
  }>;
}

export interface CustomerListParams {
  page?: number;
  per_page?: number;
  search?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export interface CustomerInput {
  email?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  phone?: string | null;
  currency?: string;
  tags?: string[];
  accepts_marketing?: boolean;
  tax_exempt?: boolean;
  note?: string | null;
  default_address?: CustomerAddress;
  addresses?: CustomerAddress[];
}

export const customersApi = {
  list: (params: CustomerListParams = {}) =>
    api
      .get<{
        data: Customer[];
        meta: { page: number; per_page: number; total: number };
      }>("/customers", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api.get<{ data: Customer }>(`/customers/${id}`).then((r) => r.data.data),

  create: (input: CustomerInput) =>
    api
      .post<{ data: Customer }>("/customers", { customer: input })
      .then((r) => r.data.data),

  update: (id: string, input: CustomerInput) =>
    api
      .patch<{ data: Customer }>(`/customers/${id}`, { customer: input })
      .then((r) => r.data.data),

  destroy: (id: string) =>
    api.delete<void>(`/customers/${id}`).then(() => true),

  bulk: (
    ids: string[],
    action_type: "delete" | "add_tag" | "remove_tag",
    payload?: Record<string, unknown>,
  ) =>
    api
      .post<{
        data: { action: string; affected: number };
      }>("/customers/bulk", { ids, action_type, payload })
      .then((r) => r.data.data),
};
