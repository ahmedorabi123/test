import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import ManualOrderPage from "./ManualOrderPage";
import { renderWithProviders } from "../test/renderWithProviders";
import { server } from "../test/server";

describe("ManualOrderPage", () => {
  it("keeps variant search disabled until a warehouse is available", async () => {
    server.use(
      http.get("*/api/v1/customers", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 100, total: 0 },
        }),
      ),
      http.get("*/api/v1/warehouses", () => HttpResponse.json({ data: [] })),
    );

    renderWithProviders(<ManualOrderPage />, { route: "/orders/new" });

    const input = await screen.findByPlaceholderText("Pick a warehouse first");
    expect(input).toBeDisabled();
  });

  it("shows all variants by default with an optional in-stock filter", async () => {
    server.use(
      http.get("*/api/v1/customers", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 100, total: 0 },
        }),
      ),
      http.get("*/api/v1/warehouses", () =>
        HttpResponse.json({
          data: [{ id: "w1", name: "Main", code: "MAIN", active: true }],
        }),
      ),
    );

    renderWithProviders(<ManualOrderPage />, { route: "/orders/new" });

    await waitFor(() => {
      expect(screen.getByLabelText(/In stock only/i)).not.toBeChecked();
    });
  });

  it("excludes Shopify warehouses and opens a dropdown of variants without a search term", async () => {
    const user = userEvent.setup();
    let variantUrl: URL | null = null;
    server.use(
      http.get("*/api/v1/customers", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 100, total: 0 },
        }),
      ),
      http.get("*/api/v1/warehouses", () =>
        HttpResponse.json({
          data: [
            { id: "w1", name: "Showroom", code: "SR", active: true },
            {
              id: "w-shopify",
              name: "Shopify",
              code: "SHOP",
              active: true,
              shopify_location_id: 123,
              read_only_origin: true,
            },
          ],
        }),
      ),
      http.get("*/api/v1/variants", ({ request }) => {
        variantUrl = new URL(request.url);
        return HttpResponse.json({
          data: [
            {
              id: "v1",
              sku: "TEE-1",
              title: "Default",
              price: "25.00",
              product_id: "prod-1",
              product_title: "Manual Tee",
              stock_items: [
                {
                  warehouse_id: "w1",
                  available: 6,
                  quantity_on_hand: 6,
                },
              ],
            },
          ],
          meta: { page: 1, per_page: 100, total: 1 },
        });
      }),
    );

    renderWithProviders(<ManualOrderPage />, { route: "/orders/new" });

    const warehouseSelect = await screen.findByLabelText(/warehouse/i);
    await waitFor(() => expect(warehouseSelect).toHaveDisplayValue("Showroom"));
    expect(screen.queryByText("Shopify")).not.toBeInTheDocument();

    await user.click(await screen.findByPlaceholderText(/search or choose/i));

    expect(await screen.findByText(/Manual Tee/)).toBeInTheDocument();
    const capturedVariantUrl = variantUrl as URL | null;
    expect(capturedVariantUrl?.searchParams.get("search")).toBeNull();
  });
});
