import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import ManualOrderPage from "./ManualOrderPage";
import { renderWithProviders } from "../test/renderWithProviders";
import { server } from "../test/server";

describe("ManualOrderPage", () => {
  it("keeps variant search disabled until a warehouse is available", async () => {
    server.use(
      http.get("*/api/v1/customers", () =>
        HttpResponse.json({ data: [], meta: { page: 1, per_page: 100, total: 0 } }),
      ),
      http.get("*/api/v1/warehouses", () => HttpResponse.json({ data: [] })),
    );

    renderWithProviders(<ManualOrderPage />, { route: "/orders/new" });

    const input = await screen.findByPlaceholderText("Pick a warehouse first");
    expect(input).toBeDisabled();
  });

  it("shows the in-stock filter by default", async () => {
    server.use(
      http.get("*/api/v1/customers", () =>
        HttpResponse.json({ data: [], meta: { page: 1, per_page: 100, total: 0 } }),
      ),
      http.get("*/api/v1/warehouses", () =>
        HttpResponse.json({
          data: [{ id: "w1", name: "Main", code: "MAIN", active: true }],
        }),
      ),
    );

    renderWithProviders(<ManualOrderPage />, { route: "/orders/new" });

    await waitFor(() => {
      expect(screen.getByLabelText(/In stock only/i)).toBeChecked();
    });
  });
});