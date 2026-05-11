import api from "./client";

export interface ProductImage {
  id?: string;
  src: string;
  alt?: string | null;
  position?: number;
  variant_id?: string | null;
  _destroy?: boolean;
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

export interface StockItemLocation {
  id: string;
  warehouse_id: string;
  warehouse_name: string;
  warehouse_code: string | null;
  quantity_on_hand: number;
  quantity_reserved?: number;
  quantity_unavailable?: number;
  available?: number;
  low_stock_threshold?: number;
}

export interface StockItemAttribute {
  id?: string;
  warehouse_id: string;
  quantity_on_hand?: number | string;
  low_stock_threshold?: number | string;
}

export interface ProductCollectionSummary {
  id: string;
  title: string;
  handle: string;
}

export interface ProductMetafield {
  namespace: string;
  key: string;
  type: string;
  value: string;
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
  cost?: string | null;
  last_purchase_cost?: string | null;
  cost_per_item?: string | null;
  stock_items?: StockItemLocation[];
}

export interface Product {
  id: string;
  title: string;
  handle: string;
  status: "active" | "draft" | "archived";
  vendor: string | null;
  product_type: string | null;
  description?: string | null;
  metafields?: ProductMetafield[];
  category_metafields?: Record<string, string | null | undefined>;
  source: "manual" | "shopify";
  shopify_product_id: number | null;
  created_at: string;
  updated_at: string;
  variants_count?: number;
  inventory_total?: number;
  variants_in_stock_count?: number;
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
  collections?: ProductCollectionSummary[];
  collection_ids?: string[];
  primary_category?: string | null;
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
  from_shopify?: boolean;
  collection_id?: string;
}

export const productsApi = {
  list: (params: ProductListParams = {}) =>
    api.get<Paginated<Product>>("/products", { params }).then((r) => r.data),

  get: (id: string) =>
    api.get<{ data: Product }>(`/products/${id}`).then((r) => r.data.data),

  create: (
    payload: Partial<Product> & {
      collection_ids?: string[];
      variants_attributes?: (Partial<Variant> & {
        stock_items_attributes?: StockItemAttribute[];
      })[];
      product_options_attributes?: ProductOption[];
      product_images_attributes?: ProductImage[];
    },
  ) =>
    api
      .post<{ data: Product }>("/products", { product: payload })
      .then((r) => r.data.data),

  update: (
    id: string,
    payload: Partial<Product> & {
      collection_ids?: string[];
      variants_attributes?: (Partial<Variant> & {
        stock_items_attributes?: StockItemAttribute[];
      })[];
      product_options_attributes?: ProductOption[];
      product_images_attributes?: ProductImage[];
    },
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

  uploadImages: (productId: string, files: File[]) => {
    const form = new FormData();
    files.forEach((f) => form.append("files[]", f));
    return api
      .post<{ data: UploadedImage[] }>(`/products/${productId}/images`, form, {
        headers: { "Content-Type": "multipart/form-data" },
      })
      .then((r) => r.data.data);
  },

  deleteImage: (productId: string, attachmentId: number | string) =>
    api
      .delete(`/products/${productId}/images/${attachmentId}`)
      .then(() => undefined),
};

export interface UploadedImage {
  id: number;
  filename: string;
  content_type: string;
  byte_size: number;
  url: string;
}
