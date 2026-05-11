import { describe, expect, it } from "vitest";
import { isOrderRefundable } from "./refundability";

describe("isOrderRefundable", () => {
  it("allows paid and partially refunded non-cancelled orders", () => {
    expect(isOrderRefundable({ status: "processing", financial_status: "paid" })).toBe(true);
    expect(
      isOrderRefundable({
        status: "fulfilled",
        financial_status: "partially_refunded",
      }),
    ).toBe(true);
  });

  it("blocks cancelled or unpaid orders", () => {
    expect(isOrderRefundable({ status: "cancelled", financial_status: "paid" })).toBe(false);
    expect(isOrderRefundable({ status: "pending", financial_status: "pending" })).toBe(false);
  });
});