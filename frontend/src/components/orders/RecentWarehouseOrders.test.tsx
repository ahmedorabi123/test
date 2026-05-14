import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { server } from "../../test/server";
import { RecentWarehouseOrders } from "./RecentWarehouseOrders";

describe("RecentWarehouseOrders", () => {
  it("loads recent orders for the selected warehouse", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/orders", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [
            {
              id: "ord-1",
              order_number: "SO-1001",
              source: "manual",
              status: "processing",
              financial_status: "paid",
              fulfillment_status: null,
              currency: "EGP",
              subtotal_price: "100.00",
              total_tax: "0.00",
              total_shipping: "0.00",
              total_discount: "0.00",
              total_price: "100.00",
              customer_email: "buyer@example.com",
              customer_name: "Buyer One",
              placed_at: "2026-05-01T10:00:00Z",
              cancelled_at: null,
              shopify_order_id: null,
              created_at: "2026-05-01T10:00:00Z",
              updated_at: "2026-05-01T10:00:00Z",
            },
          ],
          meta: {
            total: 1,
            page: 1,
            per_page: 5,
            summary: { total_value: "100.00" },
          },
        });
      }),
    );

    render(
      <MemoryRouter>
        <RecentWarehouseOrders warehouseId="w-1" warehouseName="Main" />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(new URL(lastUrl).searchParams.get("warehouse_id")).toBe("w-1");
    });
    expect(await screen.findByText("SO-1001")).toBeInTheDocument();
    expect(screen.getByText("Buyer One")).toBeInTheDocument();
  });
});
