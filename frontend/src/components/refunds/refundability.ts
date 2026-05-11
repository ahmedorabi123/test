export const REFUNDABLE_FINANCIAL_STATES: string[] = [
  "paid",
  "partially_paid",
  "partially_refunded",
];

export function isOrderRefundable(o: {
  status?: string;
  financial_status?: string;
}): boolean {
  if (!o) return false;
  if (o.status === "cancelled") return false;
  if (!o.financial_status) return false;
  return REFUNDABLE_FINANCIAL_STATES.includes(o.financial_status);
}
