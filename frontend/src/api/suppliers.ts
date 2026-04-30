import api from "./client";

export interface Supplier {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  currency: string;
  status: "active" | "inactive";
  tax_id?: string | null;
  notes?: string | null;
  address?: Record<string, unknown>;
  payment_terms?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export const suppliersApi = {
  list: (
    params: {
      page?: number;
      per_page?: number;
      search?: string;
      status?: string;
      sort?: string;
      dir?: "asc" | "desc";
    } = {},
  ) =>
    api
      .get<{
        data: Supplier[];
        meta: { page: number; per_page: number; total: number };
      }>("/suppliers", { params })
      .then((r) => r.data),
  get: (id: string) =>
    api.get<{ data: Supplier }>(`/suppliers/${id}`).then((r) => r.data.data),
  create: (payload: Partial<Supplier>) =>
    api
      .post<{ data: Supplier }>("/suppliers", { supplier: payload })
      .then((r) => r.data.data),
  update: (id: string, payload: Partial<Supplier>) =>
    api
      .patch<{ data: Supplier }>(`/suppliers/${id}`, { supplier: payload })
      .then((r) => r.data.data),
  destroy: (id: string) => api.delete(`/suppliers/${id}`).then(() => undefined),
  bulk: (ids: string[], action_type: "activate" | "deactivate") =>
    api
      .post<{ data: { action: string; affected: number } }>("/suppliers/bulk", {
        ids,
        action_type,
      })
      .then((r) => r.data.data),
};
