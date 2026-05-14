import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import ProductsPage from "./ProductsPage";

describe("ProductsPage", () => {
  it("searches while typing without requiring Enter", async () => {
    const user = userEvent.setup();
    const searches: (string | null)[] = [];

    server.use(
      http.get("*/api/v1/products", ({ request }) => {
        searches.push(new URL(request.url).searchParams.get("search"));
        return HttpResponse.json({
          data: [],
          meta: { total: 0, page: 1, per_page: 25 },
        });
      }),
    );

    renderWithProviders(<ProductsPage />, { route: "/products" });

    await user.type(screen.getByPlaceholderText(/search title/i), "tee");

    await waitFor(() => {
      expect(searches).toContain("tee");
    });
  });
});
