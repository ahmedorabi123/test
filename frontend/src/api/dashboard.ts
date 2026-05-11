import api from "./client";

export interface DashboardSummary {
  window_days: number;
  kpis: {
    revenue: number;
    orders_count: number;
    ar_outstanding: number;
    pending_shipments: number;
    pending_refunds: number;
    pending_refund_amount: number;
    low_stock_count: number;
    orders_pending: number;
  };
  revenue_trend: Array<{ date: string; revenue: number; orders: number }>;
  orders_by_status: Record<string, number>;
  delivery_breakdown: Record<string, number>;
  low_stock: Array<{
    id: string;
    warehouse: string | null;
    variant_id: string;
    sku: string | null;
    product: string | null;
    available: number;
    on_hand: number;
    reserved: number;
    threshold: number;
  }>;
  top_variants: Array<{
    variant_id: string | null;
    title: string;
    sku: string | null;
    quantity: number;
    revenue: number;
  }>;
  gross_margin: {
    revenue: number;
    cogs: number;
    margin: number;
    margin_pct: number;
  };
  recent_activity: Array<{
    kind: "order" | "shipment" | "refund";
    at: string;
    title: string;
    subtitle: string;
    amount?: number;
    currency?: string;
    link: string;
  }>;
}

export const dashboardApi = {
  summary: (window = 30) =>
    api
      .get<{ data: DashboardSummary }>("/dashboard/summary", {
        params: { window },
      })
      .then((r) => r.data.data),
};
