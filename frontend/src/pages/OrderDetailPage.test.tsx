import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import OrderDetailPage from "./OrderDetailPage";

describe("OrderDetailPage", () => {
  it("locks Shopify-origin orders and hides ERP mutation actions", async () => {
    server.use(
      http.get("*/api/v1/orders/ord-shopify", () =>
        HttpResponse.json({
          data: {
            id: "ord-shopify",
            order_number: "#1001",
            external_number: null,
            source: "shopify",
            status: "processing",
            financial_status: "paid",
            fulfillment_status: null,
            currency: "EGP",
            subtotal_price: "100.00",
            total_tax: "0.00",
            total_shipping: "0.00",
            total_discount: "0.00",
            total_price: "100.00",
            customer_email: "shop@example.com",
            customer_name: "Shop Customer",
            placed_at: "2026-01-01T00:00:00Z",
            cancelled_at: null,
            shopify_order_id: 98765,
            read_only_origin: true,
            created_at: "2026-01-01T00:00:00Z",
            updated_at: "2026-01-01T00:00:00Z",
            line_items: [],
            fulfillments: [
              {
                id: "ful-1",
                order_id: "ord-shopify",
                status: "success",
                tracking_company: "Bosta",
                tracking_number: "BST-1",
                tracking_url: null,
                carrier: "Bosta",
                delivery_status: "pending",
                notes: null,
                tags: [],
                shipped_at: null,
                delivered_at: null,
                location_id: null,
                shopify_fulfillment_id: null,
                read_only_origin: false,
                created_at: "2026-01-01T00:00:00Z",
                updated_at: "2026-01-01T00:00:00Z",
                order: {
                  id: "ord-shopify",
                  order_number: "#1001",
                  source: "shopify",
                  status: "processing",
                  financial_status: "paid",
                  total_price: "100.00",
                  currency: "EGP",
                  shopify_order_id: 98765,
                  read_only_origin: true,
                },
              },
            ],
          },
        }),
      ),
      http.get("*/api/v1/orders/ord-shopify/stock_allocation", () =>
        HttpResponse.json({ data: [] }),
      ),
      http.get("*/api/v1/orders/ord-shopify/timeline", () =>
        HttpResponse.json({ data: [] }),
      ),
    );

    renderWithProviders(
      <Routes>
        <Route path="/orders/:id" element={<OrderDetailPage />} />
      </Routes>,
      { route: "/orders/ord-shopify" },
    );

    expect(await screen.findByText(/managed by Shopify/i)).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /mark as fulfilled/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /mark partially paid/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /manual fulfillment/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /mark in transit/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: /^refunds$/i }),
    ).not.toBeInTheDocument();
  });
});