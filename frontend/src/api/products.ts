import api from "./client";

export interface ProductImage {
  id?: string;
  src: string;
  alt?: string | null;
  position?: number;
  variant_id?: string | null;
}

export interface ProductOptionValue {
  id?: string;
  value: string;
  position?: number;
}

export interface ProductOption {
  id?: string;
  name: string;
  position?: number;
  product_option_values?: ProductOptionValue[];
}

export interface Variant {
  id: string;
  sku: string | null;
  title: string;
  price: string;
  compare_at_price: string | null;
  barcode: string | null;
  position: number;
  shopify_variant_id: number | null;
  shopify_inventory_item_id: number | null;
  option1?: string | null;
  option2?: string | null;
  option3?: string | null;
  weight?: string | null;
  weight_unit?: "kg" | "g" | "lb" | "oz" | null;
  inventory_policy?: "deny" | "continue" | null;
  inventory_management?: string | null;
  requires_shipping?: boolean;
  taxable?: boolean;
  fulfillment_service?: string | null;
  hs_code?: string | null;
  country_of_origin?: string | null;
  cost_per_item?: string | null;
}

export interface Product {
  id: string;
  title: string;
  handle: string;
  status: "active" | "draft" | "archived";
  vendor: string | null;
  product_type: string | null;
  description?: string | null;
  shopify_product_id: number | null;
  created_at: string;
  updated_at: string;
  variants_count?: number;
  variants?: Variant[];
  tags?: string[];
  seo_title?: string | null;
  seo_description?: string | null;
  template_suffix?: string | null;
  published_at?: string | null;
  published_scope?: "web" | "global";
  gift_card?: boolean;
  options?: ProductOption[];
  images?: ProductImage[];
}

export interface Paginated<T> {
  data: T[];
  meta: { page: number; per_page: number; total: number };
}

export interface ProductListParams {
  page?: number;
  per_page?: number;
  search?: string;
  status?: string;
  sort?: string;
  dir?: "asc" | "desc";
}

export const productsApi = {
  list: (params: ProductListParams = {}) =>
    api.get<Paginated<Product>>("/products", { params }).then((r) => r.data),

  get: (id: string) =>
    api.get<{ data: Product }>(`/products/${id}`).then((r) => r.data.data),

  create: (
    payload: Partial<Product> & { variants_attributes?: Partial<Variant>[] },
  ) =>
    api
      .post<{ data: Product }>("/products", { product: payload })
      .then((r) => r.data.data),

  update: (
    id: string,
    payload: Partial<Product> & { variants_attributes?: Partial<Variant>[] },
  ) =>
    api
      .patch<{ data: Product }>(`/products/${id}`, { product: payload })
      .then((r) => r.data.data),

  destroy: (id: string) => api.delete(`/products/${id}`).then(() => undefined),

  bulk: (ids: string[], action_type: "archive" | "activate" | "delete") =>
    api
      .post<{
        data: { action: string; affected: number };
      }>("/products/bulk", { ids, action_type })
      .then((r) => r.data.data),
};
