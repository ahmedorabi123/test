import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import OrdersPage from "./OrdersPage";

describe("OrdersPage", () => {
  it("renders the Orders heading and an order row from the API", async () => {
    server.use(
      http.get("*/api/v1/orders", () =>
        HttpResponse.json({
          data: [
            {
              id: "ord-1",
              order_number: "SO-9001",
              status: "processing",
              financial_status: "paid",
              last_delivery_status: "in_transit",
              currency: "EGP",
              total_price: "199.99",
              source: "manual",
              created_at: "2026-04-01T10:00:00Z",
              customer: { id: "c-1", display_name: "Jane Doe", email: "jane@example.com" },
            },
          ],
          meta: { total: 1, page: 1, per_page: 25, summary: { total_value: "199.99" } },
        })
      )
    );

    renderWithProviders(<OrdersPage />, { route: "/orders" });

    expect(screen.getByText("Orders")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByText("SO-9001")).toBeInTheDocument();
    });
  });

  it("surfaces an error when /orders fails", async () => {
    server.use(
      http.get("*/api/v1/orders", () =>
        HttpResponse.json(
          { error: { detail: "service unavailable" } },
          { status: 503 }
        )
      )
    );

    renderWithProviders(<OrdersPage />, { route: "/orders" });

    await waitFor(() => {
      // OrdersPage surfaces an error banner / message somewhere in the DOM.
      expect(
        screen.getByText(/service unavailable|failed|error/i)
      ).toBeInTheDocument();
    });
  });
});
