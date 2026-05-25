import api from "./client";

export interface VariantLookup {
  id: string;
  sku: string | null;
  title: string;
  price: string;
  shopify_variant_id: number | null;
  read_only_origin?: boolean;
  product_id: string;
  product_title: string | null;
  product_source?: "manual" | "shopify";
}

export const variantsApi = {
  list: (
    params: {
      search?: string;
      q?: string;
      page?: number;
      per_page?: number;
    } = {},
  ) =>
    api
      .get<{
        data: VariantLookup[];
        meta: { page: number; per_page: number; total: number };
      }>("/variants", {
        params: {
          ...params,
          search: params.search ?? params.q,
        },
      })
      .then((r) => r.data),
};
