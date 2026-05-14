import { describe, it, expect, vi, beforeEach } from "vitest";
import { http, HttpResponse } from "msw";
import { screen, waitFor, within, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders } from "../../test/renderWithProviders";
import { server } from "../../test/server";
import { TransferStockButton, ShowroomReportButton } from "./InventoryActions";
import type { Warehouse } from "../../api/inventory";

const wh = (over: Partial<Warehouse> = {}): Warehouse => ({
  id: "w1",
  name: "Main",
  code: "MAIN",
  kind: "own",
  active: true,
  read_only_origin: false,
  address: null,
  created_at: "2025-01-01T00:00:00Z",
  updated_at: "2025-01-01T00:00:00Z",
  ...over,
});

const wh2 = wh({
  id: "w2",
  name: "Showroom",
  code: "CAIRO",
  kind: "consignment",
});
const shopifyWh = wh({
  id: "w3",
  name: "Shopify",
  code: "SHOP",
  read_only_origin: true,
});

beforeEach(() => {
  server.use(
    http.get("*/api/v1/variants", () =>
      HttpResponse.json({
        data: [
          {
            id: "v1",
            title: "Default",
            sku: "SKU1",
            product_title: "Widget",
          },
        ],
        meta: { total: 1, page: 1, per_page: 100 },
      }),
    ),
  );
});

describe("TransferStockButton", () => {
  it("submits a multi-line batch via createBatch and excludes Shopify-origin warehouses", async () => {
    const onDone = vi.fn();
    let received: unknown = null;
    server.use(
      http.post("*/api/v1/stock_transfers", async ({ request }) => {
        received = await request.json();
        return HttpResponse.json(
          {
            data: {
              id: "t1",
              reference: "TR-2025-0001",
              status: "posted",
              reason: "transfer",
              from_warehouse_id: "w1",
              to_warehouse_id: "w2",
              total_quantity: 5,
              line_count: 2,
            },
          },
          { status: 201 },
        );
      }),
    );

    renderWithProviders(
      <TransferStockButton
        warehouses={[wh(), wh2, shopifyWh]}
        onDone={onDone}
      />,
    );

    await userEvent.click(screen.getByRole("button", { name: /transfer/i }));
    const dialog1 = await screen.findByRole("dialog");

    // Shopify-origin warehouse must NOT appear in the From select.
    const fromSelect = within(dialog1).getByLabelText(
      /from \*/i,
    ) as HTMLSelectElement;
    const fromOptions = Array.from(fromSelect.options).map((o) => o.text);
    expect(fromOptions.join("|")).not.toContain("Shopify");

    await userEvent.selectOptions(fromSelect, "w1");
    await userEvent.selectOptions(
      within(dialog1).getByLabelText(/to \*/i),
      "w2",
    );

    // Wait for variants to load
    const variantSelect = await waitFor(() => {
      const sel = within(dialog1)
        .getAllByRole("combobox")
        .find((s) =>
          Array.from((s as HTMLSelectElement).options).some((o) =>
            o.text.includes("Widget"),
          ),
        ) as HTMLSelectElement | undefined;
      if (!sel) throw new Error("variant select not ready");
      return sel;
    });
    await userEvent.selectOptions(variantSelect, "v1");
    const qtyInput = within(dialog1).getByRole(
      "spinbutton",
    ) as HTMLInputElement;
    fireEvent.change(qtyInput, { target: { value: "5" } });

    await userEvent.click(
      within(dialog1).getByRole("button", { name: /^transfer$/i }),
    );

    await waitFor(() => expect(onDone).toHaveBeenCalled());

    expect(received).toEqual({
      stock_transfer: {
        from_warehouse_id: "w1",
        to_warehouse_id: "w2",
        reason: "transfer",
      },
      lines: [{ variant_id: "v1", quantity: 5 }],
    });
  });

  it("shows an error from the API when source has insufficient stock", async () => {
    server.use(
      http.post("*/api/v1/stock_transfers", () =>
        HttpResponse.json(
          {
            error: {
              status: 422,
              type: "insufficient_stock",
              detail:
                "Insufficient stock for variant v1 at MAIN: requested 5, available 0",
              code: { variant_id: "v1", available: 0, requested: 5 },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(
      <TransferStockButton warehouses={[wh(), wh2]} onDone={vi.fn()} />,
    );
    await userEvent.click(screen.getByRole("button", { name: /transfer/i }));
    const dialog2 = await screen.findByRole("dialog");

    await userEvent.selectOptions(
      within(dialog2).getByLabelText(/from \*/i),
      "w1",
    );
    await userEvent.selectOptions(
      within(dialog2).getByLabelText(/to \*/i),
      "w2",
    );

    const variantSelect = await waitFor(() => {
      const sel = within(dialog2)
        .getAllByRole("combobox")
        .find((s) =>
          Array.from((s as HTMLSelectElement).options).some((o) =>
            o.text.includes("Widget"),
          ),
        ) as HTMLSelectElement | undefined;
      if (!sel) throw new Error("variant select not ready");
      return sel;
    });
    await userEvent.selectOptions(variantSelect, "v1");
    const qtyInput = within(dialog2).getByRole(
      "spinbutton",
    ) as HTMLInputElement;
    fireEvent.change(qtyInput, { target: { value: "5" } });

    await userEvent.click(
      within(dialog2).getByRole("button", { name: /^transfer$/i }),
    );

    expect(await screen.findByText(/Insufficient stock/i)).toBeInTheDocument();
  });
});

describe("ShowroomReportButton", () => {
  it("accepts a negative quantity line and shows the reversal total in the success toast", async () => {
    let received: unknown = null;
    server.use(
      http.post("*/api/v1/showroom_sales", async ({ request }) => {
        received = await request.json();
        return HttpResponse.json(
          {
            data: {
              order: null,
              reversal: {
                id: "rv1",
                warehouse_id: "w2",
                period: "2025-03",
                currency: "EGP",
                total_amount: "50.00",
                idempotency_key: "showroom-reversal-w2-2025-03",
                lines: [
                  { variant_id: "v1", quantity: -1, unit_price: "50.00" },
                ],
              },
              sales_total: "0.0",
              reversal_total: "50.00",
            },
          },
          { status: 201 },
        );
      }),
    );

    renderWithProviders(
      <ShowroomReportButton warehouses={[wh2]} onDone={vi.fn()} />,
    );

    await userEvent.click(
      screen.getByRole("button", { name: /showroom report/i }),
    );
    const dialog = await screen.findByRole("dialog");

    await userEvent.selectOptions(
      within(dialog).getByLabelText(/showroom \*/i),
      "w2",
    );

    const variantSelect = await waitFor(() => {
      const sel = within(dialog)
        .getAllByRole("combobox")
        .find((s) =>
          Array.from((s as HTMLSelectElement).options).some((o) =>
            o.text.includes("Widget"),
          ),
        ) as HTMLSelectElement | undefined;
      if (!sel) throw new Error("variant select not ready");
      return sel;
    });
    await userEvent.selectOptions(variantSelect, "v1");

    const qty = within(dialog).getByLabelText(/quantity/i) as HTMLInputElement;
    fireEvent.change(qty, { target: { value: "-1" } });
    // The price field is the second spinbutton in the line row.
    const spinbuttons = within(dialog).getAllByRole("spinbutton");
    const priceInput = spinbuttons[spinbuttons.length - 1] as HTMLInputElement;
    fireEvent.change(priceInput, { target: { value: "50" } });

    await userEvent.click(
      within(dialog).getByRole("button", { name: /post report/i }),
    );

    await waitFor(() => {
      expect((received as { line_items: unknown[] }).line_items).toEqual([
        { variant_id: "v1", quantity: -1, unit_price: "50" },
      ]);
    });

    expect(
      await screen.findByTestId("showroom-reversal-total"),
    ).toHaveTextContent("50.00");
  });
});
