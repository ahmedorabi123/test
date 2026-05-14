import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import NewPurchaseOrderPage from "./NewPurchaseOrderPage";

describe("NewPurchaseOrderPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("loads only factory suppliers and hides unit cost inputs", async () => {
    let suppliersUrl = "";
    server.use(
      http.get("*/api/v1/suppliers", ({ request }) => {
        suppliersUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 100, total: 0 },
        });
      }),
      http.get("*/api/v1/warehouses", () => HttpResponse.json({ data: [] })),
      http.get("*/api/v1/products", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 100, total: 0 },
        }),
      ),
    );

    renderWithProviders(<NewPurchaseOrderPage />, { route: "/purchases/new" });

    await waitFor(() => {
      expect(new URL(suppliersUrl).searchParams.get("kind")).toBe("factory");
    });
    expect(screen.queryByText(/unit cost/i)).not.toBeInTheDocument();
  });
});
