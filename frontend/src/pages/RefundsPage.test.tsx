import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import RefundsPage from "./RefundsPage";

describe("RefundsPage", () => {
  it("renders the empty state when the API returns no refunds", async () => {
    renderWithProviders(<RefundsPage />, { route: "/refunds" });
    await waitFor(() => {
      expect(screen.getByText(/No refunds found\./i)).toBeInTheDocument();
    });
  });

  it("renders a refund row when the API returns one", async () => {
    server.use(
      http.get("*/api/v1/refunds", () =>
        HttpResponse.json({
          data: [
            {
              id: "rf-1",
              order_id: "ord-1",
              order: {
                id: "ord-1",
                order_number: "SO-0001",
                total_price: "100.00",
                total_refunded: "25.00",
                currency: "EGP",
                status: "processing",
                financial_status: "partially_refunded",
              },
              amount: "25.00",
              currency: "EGP",
              reason: "damaged",
              note: null,
              status: "processed",
              kind: "manual",
              processed_at: "2026-01-01T10:00:00Z",
              restock: true,
              inventory_restocked: true,
              shopify_refund_id: null,
              partial: true,
              full: false,
              created_at: "2026-01-01T10:00:00Z",
              updated_at: "2026-01-01T10:00:00Z",
              line_items: [],
            },
          ],
          meta: { total: 1, page: 1, per_page: 25 },
        })
      )
    );

    renderWithProviders(<RefundsPage />, { route: "/refunds" });

    await waitFor(() => {
      expect(screen.getByText("SO-0001")).toBeInTheDocument();
    });
    expect(screen.getByText(/damaged/i)).toBeInTheDocument();
  });

  it("renders an error banner when the API fails", async () => {
    server.use(
      http.get("*/api/v1/refunds", () =>
        HttpResponse.json(
          { error: { detail: "boom" } },
          { status: 500 }
        )
      )
    );

    renderWithProviders(<RefundsPage />, { route: "/refunds" });

    await waitFor(() => {
      expect(
        screen.getByText(/failed|boom|error/i)
      ).toBeInTheDocument();
    });
  });
});
