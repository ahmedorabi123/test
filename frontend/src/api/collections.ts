import api from "./client";

export interface CollectionRule {
  column: string;
  relation: string;
  condition: string;
}

export interface CollectionProduct {
  id: string;
  title: string;
  handle: string;
  status: string;
  image?: string | null;
}

export interface Collection {
  id: string;
  shopify_collection_id?: number | null;
  title: string;
  handle: string;
  body_html?: string | null;
  image?: string | null;
  sort_order?: string;
  published_at?: string | null;
  published_scope?: string;
  kind: "custom" | "smart";
  source: "manual" | "shopify";
  read_only_origin?: boolean;
  rules?: CollectionRule[];
  disjunctive?: boolean;
  products_count: number;
  products?: CollectionProduct[];
  shopify_updated_at?: string | null;
  created_at: string;
  updated_at: string;
}

export interface CollectionListParams {
  page?: number;
  per_page?: number;
  search?: string;
  kind?: "custom" | "smart";
  sort?: string;
  dir?: "asc" | "desc";
}

export interface Paginated<T> {
  data: T[];
  meta: {
    page: number;
    per_page: number;
    total: number;
    kind_counts?: Record<"custom" | "smart", number>;
  };
}

export const collectionsApi = {
  list: (params: CollectionListParams = {}) =>
    api
      .get<Paginated<Collection>>("/collections", { params })
      .then((r) => r.data),

  get: (id: string) =>
    api
      .get<{ data: Collection }>(`/collections/${id}`)
      .then((r) => r.data.data),

  create: (payload: Partial<Collection>) =>
    api
      .post<{ data: Collection }>("/collections", { collection: payload })
      .then((r) => r.data.data),

  update: (id: string, payload: Partial<Collection>) =>
    api
      .patch<{ data: Collection }>(`/collections/${id}`, {
        collection: payload,
      })
      .then((r) => r.data.data),

  destroy: (id: string) =>
    api.delete(`/collections/${id}`).then(() => undefined),

  addProduct: (collectionId: string, productId: string, position?: number) =>
    api
      .post<{
        data: Collection;
      }>(`/collections/${collectionId}/products`, {
        product_id: productId,
        position,
      })
      .then((r) => r.data.data),

  removeProduct: (collectionId: string, productId: string) =>
    api
      .delete<{
        data: Collection;
      }>(`/collections/${collectionId}/products/${productId}`)
      .then((r) => r.data.data),
};
