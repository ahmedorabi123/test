import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import NewProductPage from "./NewProductPage";

describe("NewProductPage", () => {
  it("creates products without stock mutations and uploads selected media", async () => {
    const user = userEvent.setup();
    let productPayload: unknown = null;
    let uploadedNames: string[] = [];

    server.use(
      http.post("*/api/v1/products", async ({ request }) => {
        productPayload = await request.json();
        return HttpResponse.json({
          data: {
            id: "prod-1",
            title: "Manual Tee",
            handle: "manual-tee",
            status: "active",
            vendor: null,
            product_type: null,
            source: "manual",
            shopify_product_id: null,
            created_at: "2026-01-01T00:00:00Z",
            updated_at: "2026-01-01T00:00:00Z",
          },
        });
      }),
      http.post("*/api/v1/products/prod-1/images", async ({ request }) => {
        const form = await request.formData();
        uploadedNames = form
          .getAll("files[]")
          .map((value) => (value as File).name)
          .filter(Boolean);
        return HttpResponse.json(
          {
            data: uploadedNames.map((name, index) => ({
              id: index + 1,
              filename: name,
              content_type: "image/png",
              byte_size: 5,
              url: `/rails/active_storage/${name}`,
            })),
          },
          { status: 201 },
        );
      }),
    );

    renderWithProviders(
      <Routes>
        <Route path="/products/new" element={<NewProductPage />} />
        <Route path="/products/:id" element={<div>Product detail</div>} />
      </Routes>,
      { route: "/products/new" },
    );

    expect(screen.queryByText(/generate variants/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^stock$/i)).not.toBeInTheDocument();

    await user.type(screen.getByLabelText(/^title$/i), "Manual Tee");
    await user.type(screen.getByLabelText(/variant 1 sku/i), "TEE-1");
    await user.upload(
      screen.getByLabelText(/upload product media/i),
      new File(["image"], "tee.png", { type: "image/png" }),
    );
    await user.click(screen.getByRole("button", { name: /create product/i }));

    await waitFor(() => {
      expect(uploadedNames).toEqual(["tee.png"]);
    });
    expect(JSON.stringify(productPayload)).not.toContain(
      "stock_items_attributes",
    );
    expect(JSON.stringify(productPayload)).not.toContain(
      "compare_at_price",
    );
    expect(JSON.stringify(productPayload)).not.toContain("cost_per_item");
    expect(JSON.stringify(productPayload)).not.toContain("barcode");
    expect(JSON.stringify(productPayload)).not.toContain(
      "product_options_attributes",
    );
    expect(productPayload).toMatchObject({
      product: {
        title: "Manual Tee",
        variants_attributes: [expect.objectContaining({ sku: "TEE-1" })],
      },
    });
  });
});
