import api from "./client";

export interface AuditLogEntry {
  id: string;
  action: string;
  subject_type: string | null;
  subject_id: string | null;
  user: { id: string; email: string } | null;
  ip_address: string | null;
  user_agent: string | null;
  diff: Record<string, unknown> | null;
  occurred_at: string;
}

export interface AuditLogListParams {
  page?: number;
  per_page?: number;
  action_type?: string;
  subject_type?: string;
  user_id?: string;
  q?: string;
  actor_email?: string;
  from_date?: string;
  to_date?: string;
}

export const auditLogsApi = {
  list: (params: AuditLogListParams = {}) =>
    api
      .get<{
        data: AuditLogEntry[];
        meta: { page: number; per_page: number; total: number };
      }>("/audit_logs", { params })
      .then((r) => r.data),
};
