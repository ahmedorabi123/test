import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import PurchasesPage from "./PurchasesPage";

const SAMPLE_PO = {
  id: "po-1",
  po_number: "PO-1001",
  supplier_id: "s-1",
  supplier_name: "Acme Supplies",
  warehouse_id: "w-1",
  warehouse_name: "Main",
  status: "ordered",
  currency: "USD",
  subtotal: "100.00",
  total_tax: "0",
  total_shipping: "0",
  total: "100.00",
  ordered_at: null,
  expected_at: "2026-05-01T00:00:00Z",
  received_at: null,
  notes: null,
  created_at: "2026-04-01T10:00:00Z",
  updated_at: "2026-04-01T10:00:00Z",
};

describe("PurchasesPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("renders heading + new PO link", async () => {
    server.use(
      http.get("*/api/v1/purchase_orders", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 25, total: 0 },
        }),
      ),
    );
    renderWithProviders(<PurchasesPage />, { route: "/purchases" });
    expect(
      screen.getByRole("heading", { name: /Purchase Orders/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /\+ New PO/i })).toHaveAttribute(
      "href",
      "/purchases/new",
    );
  });

  it("renders a PO row from the API", async () => {
    server.use(
      http.get("*/api/v1/purchase_orders", () =>
        HttpResponse.json({
          data: [SAMPLE_PO],
          meta: { page: 1, per_page: 25, total: 1 },
        }),
      ),
    );
    renderWithProviders(<PurchasesPage />, { route: "/purchases" });
    await waitFor(() => {
      expect(screen.getByText("PO-1001")).toBeInTheDocument();
    });
    expect(screen.getByText("Acme Supplies")).toBeInTheDocument();
  });

  it("sends sort + dir params when clicking a sortable column header", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/purchase_orders", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [SAMPLE_PO],
          meta: { page: 1, per_page: 25, total: 1 },
        });
      }),
    );
    renderWithProviders(<PurchasesPage />, { route: "/purchases" });
    await waitFor(() =>
      expect(screen.getByText("PO-1001")).toBeInTheDocument(),
    );

    const header = screen.getByRole("columnheader", { name: /PO #/i });
    await userEvent.click(header);

    await waitFor(() => {
      expect(lastUrl).toMatch(/sort=po_number/);
      expect(lastUrl).toMatch(/dir=asc/);
    });
  });

  it("changes per_page via selector", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/purchase_orders", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [SAMPLE_PO],
          meta: { page: 1, per_page: 25, total: 1 },
        });
      }),
    );
    renderWithProviders(<PurchasesPage />, { route: "/purchases" });
    await waitFor(() =>
      expect(screen.getByText("PO-1001")).toBeInTheDocument(),
    );

    const perPageSelect = screen.getByLabelText(/Per page/i);
    await userEvent.selectOptions(perPageSelect, "50");

    await waitFor(() => {
      expect(lastUrl).toMatch(/per_page=50/);
    });
  });

  it("filters by status via the status selector", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/purchase_orders", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 25, total: 0 },
        });
      }),
    );
    renderWithProviders(<PurchasesPage />, { route: "/purchases" });

    // First status select on the page (filter, not per-page)
    const filter = screen
      .getAllByRole("combobox")
      .find((el) => within(el as HTMLElement).queryByText(/All statuses/i));
    expect(filter).toBeTruthy();
    await userEvent.selectOptions(filter as HTMLElement, "draft");

    await waitFor(() => {
      expect(lastUrl).toMatch(/status=draft/);
    });
  });
});
