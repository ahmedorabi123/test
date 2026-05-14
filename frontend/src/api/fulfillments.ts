import api from "./client";

export interface Fulfillment {
  id: string;
  order_id: string;
  order?: {
    id: string;
    order_number: string;
    source?: "manual" | "shopify" | "showroom";
    status: string;
    financial_status: string;
    fulfillment_status?: string | null;
    total_price: string;
    currency: string;
    shopify_order_id?: number | null;
    read_only_origin?: boolean;
    shipping_address?: Record<string, unknown>;
  } | null;
  customer?: {
    id?: string | null;
    name?: string | null;
    email?: string | null;
    phone?: string | null;
  } | null;
  status: string;
  tracking_company: string | null;
  tracking_number: string | null;
  tracking_url: string | null;
  carrier: string | null;
  delivery_status?: string | null;
  service?: string | null;
  notes?: string | null;
  tags?: string[];
  carrier_data?: Record<string, unknown>;
  shipped_at: string | null;
  delivered_at: string | null;
  in_transit_at?: string | null;
  location_id: number | null;
  shopify_fulfillment_id: number | null;
  read_only_origin?: boolean;
  created_at: string;
  updated_at: string;
  line_items?: Array<{
    id: string;
    fulfillment_id: string;
    order_line_item_id: string | null;
    quantity: number;
    title?: string | null;
    sku?: string | null;
    variant_title?: string | null;
  }>;
}

export interface ShipmentEvent {
  id: string;
  fulfillment_id: string;
  kind: string;
  payload: Record<string, unknown>;
  actor_id?: string | null;
  actor_name?: string | null;
  created_at: string;
}

export interface FulfillmentListParams {
  page?: number;
  per_page?: number;
  order_id?: string;
  carrier?: string;
  status?: string;
  delivery_status?: string;
  source?: string;
  search?: string;
  from?: string;
  to?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export const fulfillmentsApi = {
  list: (params: FulfillmentListParams = {}) =>
    api
      .get<{
        data: Fulfillment[];
        meta: { page: number; per_page: number; total: number };
      }>("/fulfillments", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api
      .get<{ data: Fulfillment }>(`/fulfillments/${id}`)
      .then((r) => r.data.data),

  events: (id: string) =>
    api
      .get<{ data: ShipmentEvent[] }>(`/fulfillments/${id}/events`)
      .then((r) => r.data.data),

  annotate: (id: string, payload: { notes?: string | null; tags?: string[] }) =>
    api
      .patch<{ data: Fulfillment }>(`/fulfillments/${id}/annotation`, {
        fulfillment: payload,
      })
      .then((r) => r.data.data),

  create: (payload: {
    order_id: string;
    tracking_company: string;
    tracking_number?: string;
    tracking_url?: string;
    service?: string;
    shipped_at?: string;
    transition_order?: boolean;
    line_items?: Array<{ order_line_item_id: string; quantity: number }>;
  }) =>
    api
      .post<{ data: Fulfillment }>("/fulfillments", { fulfillment: payload })
      .then((r) => r.data.data),

  transitionDelivery: (
    id: string,
    to: "in_transit" | "delivered" | "failed",
    note?: string,
  ) =>
    api
      .post<{ data: Fulfillment }>(`/fulfillments/${id}/transition_delivery`, {
        to,
        note,
      })
      .then((r) => r.data.data),
};
