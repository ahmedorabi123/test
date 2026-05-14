import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import SuppliersPage from "./SuppliersPage";

const SUPPLIER = {
  id: "sup-1",
  supplier_code: "FAC-1",
  name: "Factory One",
  kind: "factory",
  email: null,
  phone: null,
  currency: "EGP",
  status: "active",
  created_at: "2026-04-01T10:00:00Z",
  updated_at: "2026-04-01T10:00:00Z",
};

describe("SuppliersPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("filters suppliers by kind", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/suppliers", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [SUPPLIER],
          meta: { page: 1, per_page: 25, total: 1 },
        });
      }),
    );

    renderWithProviders(<SuppliersPage />, { route: "/suppliers" });
    await userEvent.selectOptions(
      await screen.findByTestId("suppliers-kind-filter"),
      "material",
    );

    await waitFor(() => {
      expect(new URL(lastUrl).searchParams.get("kind")).toBe("material");
    });
  });
});
