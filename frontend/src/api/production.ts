import api from "./client";

export interface ProductionStage {
  id: string;
  production_order_id: string;
  position: number;
  name: string;
  status: "pending" | "in_progress" | "completed" | "skipped";
  supplier_id: string | null;
  supplier_name: string | null;
  unit_cost: string | null;
  cost_currency: string | null;
  started_at: string | null;
  completed_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface ProductionOrder {
  id: string;
  number: string;
  status: "draft" | "in_progress" | "completed" | "cancelled";
  quantity: string;
  parent_variant_id: string;
  parent_variant?: {
    id: string;
    sku: string | null;
    title: string | null;
    product_title: string | null;
  } | null;
  warehouse_id: string;
  warehouse_name?: string | null;
  production_mode?: "single" | "staged";
  unit_cost?: string | null;
  cost_currency?: string | null;
  computed_unit_cost?: string | null;
  total_cost?: string | null;
  notes?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  cancelled_at?: string | null;
  created_at: string;
  updated_at: string;
  stages?: ProductionStage[];
}

export interface ProductionOrderListParams {
  page?: number;
  per_page?: number;
  status?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export const productionOrdersApi = {
  list: (params: ProductionOrderListParams = {}) =>
    api
      .get<{
        data: ProductionOrder[];
        meta: { page: number; per_page: number; total: number };
      }>("/production_orders", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api
      .get<{ data: ProductionOrder }>(`/production_orders/${id}`)
      .then((r) => r.data.data),

  create: (payload: {
    parent_variant_id: string;
    warehouse_id: string;
    quantity: number;
    notes?: string;
  }) =>
    api
      .post<{
        data: ProductionOrder;
      }>("/production_orders", { production_order: payload })
      .then((r) => r.data.data),

  update: (id: string, payload: Partial<{ quantity: number; notes: string }>) =>
    api
      .patch<{
        data: ProductionOrder;
      }>(`/production_orders/${id}`, { production_order: payload })
      .then((r) => r.data.data),

  run: (id: string) =>
    api
      .post<{ data: ProductionOrder }>(`/production_orders/${id}/run`)
      .then((r) => r.data.data),

  cancel: (id: string) =>
    api
      .post<{ data: ProductionOrder }>(`/production_orders/${id}/cancel`)
      .then((r) => r.data.data),

  destroy: (id: string) =>
    api.delete(`/production_orders/${id}`).then((r) => r.data),
};

export const productionStagesApi = {
  add: (
    poId: string,
    payload: {
      name: string;
      supplier_id?: string | null;
      unit_cost?: number | null;
      cost_currency?: string | null;
      notes?: string | null;
    },
  ) =>
    api
      .post<{ data: ProductionStage }>(`/production_orders/${poId}/stages`, {
        stage: payload,
      })
      .then((r) => r.data.data),

  update: (
    poId: string,
    stageId: string,
    payload: Partial<{
      name: string;
      supplier_id: string | null;
      unit_cost: number | null;
      cost_currency: string | null;
      notes: string | null;
      status: string;
      position: number;
    }>,
  ) =>
    api
      .patch<{
        data: ProductionStage;
      }>(`/production_orders/${poId}/stages/${stageId}`, { stage: payload })
      .then((r) => r.data.data),

  start: (poId: string, stageId: string) =>
    api
      .post<{
        data: ProductionStage;
      }>(`/production_orders/${poId}/stages/${stageId}/start`)
      .then((r) => r.data.data),

  complete: (poId: string, stageId: string) =>
    api
      .post<{
        data: ProductionStage;
      }>(`/production_orders/${poId}/stages/${stageId}/complete`)
      .then((r) => r.data.data),

  destroy: (poId: string, stageId: string) =>
    api
      .delete(`/production_orders/${poId}/stages/${stageId}`)
      .then((r) => r.data),
};

export interface Variant {
  id: string;
  sku: string;
  title: string | null;
  price: string;
  product_id: string;
  product_title: string;
}

export const variantsApi = {
  search: (q: string, product_id?: string) =>
    api
      .get<{
        data: Variant[];
      }>("/variants", { params: { search: q, product_id } })
      .then((r) => r.data.data),
};

export interface BomItem {
  id: string;
  parent_variant_id: string;
  component_variant_id: string;
  component?: {
    id: string;
    sku: string | null;
    title: string | null;
    product_title: string | null;
  } | null;
  quantity: string;
  waste_factor: string;
}

export const bomItemsApi = {
  list: (variantId: string) =>
    api
      .get<{ data: BomItem[] }>(`/variants/${variantId}/bom_items`)
      .then((r) => r.data.data),

  create: (
    variantId: string,
    payload: {
      component_variant_id: string;
      quantity: number;
      waste_factor?: number;
    },
  ) =>
    api
      .post<{
        data: BomItem;
      }>(`/variants/${variantId}/bom_items`, { bom_item: payload })
      .then((r) => r.data.data),

  update: (
    variantId: string,
    id: string,
    payload: Partial<{ quantity: number; waste_factor: number }>,
  ) =>
    api
      .patch<{
        data: BomItem;
      }>(`/variants/${variantId}/bom_items/${id}`, { bom_item: payload })
      .then((r) => r.data.data),

  destroy: (variantId: string, id: string) =>
    api.delete(`/variants/${variantId}/bom_items/${id}`).then((r) => r.data),
};
