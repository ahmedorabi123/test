import api from "./client";
import type { AxiosResponse } from "axios";

export interface UserRole {
  id: string;
  name: string;
}

export interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  active: boolean;
  last_login_at?: string | null;
  roles: UserRole[];
}

export interface Role {
  id: string;
  name: string;
  description?: string;
  system?: boolean;
  permissions: string[]; // "resource:action"
}

export interface PermissionDef {
  id?: string;
  key: string;
  resource: string;
  action: string;
  description?: string | null;
}

export const usersApi = {
  list: (): Promise<{ data: User[] }> =>
    api
      .get<{ data: User[] }>("/users")
      .then((r: AxiosResponse<{ data: User[] }>) => r.data),

  get: (id: string): Promise<{ data: User }> =>
    api
      .get<{ data: User }>(`/users/${id}`)
      .then((r: AxiosResponse<{ data: User }>) => r.data),

  create: (payload: {
    email: string;
    first_name: string;
    last_name: string;
    password?: string;
  }): Promise<{ data: User }> =>
    api
      .post<{ data: User }>("/users", { user: payload })
      .then((r: AxiosResponse<{ data: User }>) => r.data),

  update: (
    id: string,
    payload: { first_name?: string; last_name?: string; active?: boolean },
  ): Promise<{ data: User }> =>
    api
      .patch<{ data: User }>(`/users/${id}`, { user: payload })
      .then((r: AxiosResponse<{ data: User }>) => r.data),

  deactivate: (id: string): Promise<{ message: string }> =>
    api.delete<{ message: string }>(`/users/${id}`).then((r) => r.data),

  assignRole: (
    userId: string,
    roleId: string,
    warehouseId?: string,
  ): Promise<{ data: User }> =>
    api
      .post<{ data: User }>(`/users/${userId}/assign_role`, {
        role_id: roleId,
        warehouse_id: warehouseId,
      })
      .then((r: AxiosResponse<{ data: User }>) => r.data),

  removeRole: (userId: string, roleId: string): Promise<{ data: User }> =>
    api
      .delete<{
        data: User;
      }>(`/users/${userId}/remove_role`, { data: { role_id: roleId } })
      .then((r: AxiosResponse<{ data: User }>) => r.data),
};

export const rolesApi = {
  list: (): Promise<{ data: Role[] }> =>
    api
      .get<{ data: Role[] }>("/roles")
      .then((r: AxiosResponse<{ data: Role[] }>) => r.data),

  get: (id: string): Promise<{ data: Role }> =>
    api
      .get<{ data: Role }>(`/roles/${id}`)
      .then((r: AxiosResponse<{ data: Role }>) => r.data),

  create: (payload: {
    name: string;
    description?: string;
    permissions: string[];
  }): Promise<{ data: Role }> =>
    api
      .post<{ data: Role }>("/roles", { role: payload })
      .then((r: AxiosResponse<{ data: Role }>) => r.data),

  update: (
    id: string,
    payload: {
      name?: string;
      description?: string;
      permissions?: string[];
    },
  ): Promise<{ data: Role }> =>
    api
      .patch<{ data: Role }>(`/roles/${id}`, { role: payload })
      .then((r: AxiosResponse<{ data: Role }>) => r.data),

  destroy: (id: string): Promise<{ message: string }> =>
    api.delete<{ message: string }>(`/roles/${id}`).then((r) => r.data),
};

export const permissionsApi = {
  list: (): Promise<{ data: PermissionDef[] }> =>
    api
      .get<{ data: PermissionDef[] }>("/permissions")
      .then((r: AxiosResponse<{ data: PermissionDef[] }>) => r.data),
};
