import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import OrdersPage from "./OrdersPage";

describe("OrdersPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

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
              customer: {
                id: "c-1",
                display_name: "Jane Doe",
                email: "jane@example.com",
              },
            },
          ],
          meta: {
            total: 1,
            page: 1,
            per_page: 25,
            summary: { total_value: "199.99" },
          },
        }),
      ),
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
          { status: 503 },
        ),
      ),
    );

    renderWithProviders(<OrdersPage />, { route: "/orders" });

    await waitFor(() => {
      // OrdersPage surfaces an error banner / message somewhere in the DOM.
      expect(
        screen.getByText(/service unavailable|failed|error/i),
      ).toBeInTheDocument();
    });
  });

  it("places the Delivery column before the Delivery method column", async () => {
    server.use(
      http.get("*/api/v1/orders", () =>
        HttpResponse.json({
          data: [],
          meta: {
            total: 0,
            page: 1,
            per_page: 25,
            summary: { total_value: "0" },
          },
        }),
      ),
    );
    renderWithProviders(<OrdersPage />, { route: "/orders" });
    await waitFor(() => {
      expect(
        screen.getByText(/No records found|No orders/i),
      ).toBeInTheDocument();
    });
    const headers = screen
      .getAllByRole("columnheader")
      .map((c) => c.textContent || "");
    const deliveryIdx = headers.findIndex(
      (t) => /Delivery/i.test(t) && !/Delivery method/i.test(t),
    );
    const methodIdx = headers.findIndex((t) => /Delivery method/i.test(t));
    expect(deliveryIdx).toBeGreaterThanOrEqual(0);
    expect(methodIdx).toBeGreaterThanOrEqual(0);
    expect(deliveryIdx).toBeLessThan(methodIdx);
  });

  it("does not expose the retired refunded quick filter", async () => {
    server.use(
      http.get("*/api/v1/orders", () =>
        HttpResponse.json({
          data: [],
          meta: {
            total: 0,
            page: 1,
            per_page: 25,
            summary: { total_value: "0" },
          },
        }),
      ),
    );

    renderWithProviders(<OrdersPage />, { route: "/orders" });

    await waitFor(() => {
      expect(
        screen.getByText(/No records found|No orders/i),
      ).toBeInTheDocument();
    });
    expect(
      screen.queryByRole("button", { name: /^refunded$/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("option", { name: /^refunded$/i }),
    ).not.toBeInTheDocument();
  });

  it("sends warehouse_id when filtering by warehouse", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/warehouses", () =>
        HttpResponse.json({
          data: [{ id: "w-1", name: "Main", code: "MAIN", active: true }],
        }),
      ),
      http.get("*/api/v1/orders", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: {
            total: 0,
            page: 1,
            per_page: 25,
            summary: { total_value: "0" },
          },
        });
      }),
    );

    renderWithProviders(<OrdersPage />, { route: "/orders" });
    await screen.findByRole("option", { name: "Main" });
    await userEvent.selectOptions(
      screen.getByTestId("orders-warehouse-filter"),
      "w-1",
    );

    await waitFor(() => {
      expect(new URL(lastUrl).searchParams.get("warehouse_id")).toBe("w-1");
    });
  });
});
