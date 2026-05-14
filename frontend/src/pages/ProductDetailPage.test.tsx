import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import ProductDetailPage from "./ProductDetailPage";

describe("ProductDetailPage", () => {
  it("uploads images when an editable product has no media", async () => {
    const user = userEvent.setup();
    let uploadedNames: string[] = [];
    server.use(
      http.get("*/api/v1/products/prod-empty", () =>
        HttpResponse.json({
          data: {
            id: "prod-empty",
            title: "Manual Tee",
            handle: "manual-tee",
            description: "",
            status: "active",
            vendor: "ACME",
            product_type: "Apparel",
            tags: [],
            source: "manual",
            shopify_product_id: null,
            read_only_origin: false,
            created_at: "2026-01-01T00:00:00Z",
            updated_at: "2026-01-01T00:00:00Z",
            variants_count: 0,
            inventory_total: 0,
            variants_in_stock_count: 0,
            variants: [],
            images: [],
            uploaded_images: [],
            collections: [],
            collection_ids: [],
            metafields: [],
          },
        }),
      ),
      http.post("*/api/v1/products/prod-empty/images", async ({ request }) => {
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
        <Route path="/products/:id" element={<ProductDetailPage />} />
      </Routes>,
      { route: "/products/prod-empty" },
    );

    expect(await screen.findByRole("button", { name: /add image/i })).toBeInTheDocument();
    await user.upload(
      screen.getByLabelText(/upload product images/i),
      new File(["image"], "back.png", { type: "image/png" }),
    );

    await waitFor(() => expect(uploadedNames).toEqual(["back.png"]));
    expect(await screen.findByAltText("back.png")).toBeInTheDocument();
  });

  it("renders uploaded local product images", async () => {
    server.use(
      http.get("*/api/v1/products/prod-uploaded", () =>
        HttpResponse.json({
          data: {
            id: "prod-uploaded",
            title: "Manual Tee",
            handle: "manual-tee",
            description: "",
            status: "active",
            vendor: "ACME",
            product_type: "Apparel",
            tags: [],
            source: "manual",
            shopify_product_id: null,
            read_only_origin: false,
            created_at: "2026-01-01T00:00:00Z",
            updated_at: "2026-01-01T00:00:00Z",
            variants_count: 0,
            inventory_total: 0,
            variants_in_stock_count: 0,
            variants: [],
            images: [],
            uploaded_images: [
              {
                id: 1,
                filename: "front.png",
                url: "/rails/active_storage/blobs/front.png",
              },
            ],
            collections: [],
            collection_ids: [],
            metafields: [],
          },
        }),
      ),
    );

    renderWithProviders(
      <Routes>
        <Route path="/products/:id" element={<ProductDetailPage />} />
      </Routes>,
      { route: "/products/prod-uploaded" },
    );

    expect(
      await screen.findByRole("heading", { name: /^media$/i }),
    ).toBeInTheDocument();
    expect(await screen.findByAltText("front.png")).toBeInTheDocument();
  });

  it("renders Shopify-origin products as read-only", async () => {
    server.use(
      http.get("*/api/v1/products/prod-1", () =>
        HttpResponse.json({
          data: {
            id: "prod-1",
            title: "Shopify Tee",
            handle: "shopify-tee",
            description: "",
            status: "active",
            vendor: "ACME",
            product_type: "Apparel",
            tags: [],
            source: "shopify",
            shopify_product_id: 123,
            read_only_origin: true,
            created_at: "2026-01-01T00:00:00Z",
            updated_at: "2026-01-01T00:00:00Z",
            variants_count: 1,
            inventory_total: 0,
            variants_in_stock_count: 0,
            variants: [
              {
                id: "var-1",
                sku: "TEE-1",
                title: "Default",
                price: "25.00",
                compare_at_price: null,
                barcode: null,
                position: 1,
                shopify_variant_id: 456,
                shopify_inventory_item_id: 789,
                read_only_origin: true,
                stock_items: [],
              },
            ],
            images: [],
            collections: [],
            collection_ids: [],
            metafields: [],
          },
        }),
      ),
    );

    renderWithProviders(
      <Routes>
        <Route path="/products/:id" element={<ProductDetailPage />} />
      </Routes>,
      { route: "/products/prod-1" },
    );

    expect(await screen.findByText("Shopify-managed")).toBeInTheDocument();
    expect(
      screen.getByText(/managed by Shopify and cannot be edited/i),
    ).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.queryByRole("button", { name: /archive/i })).toBeNull();
      expect(screen.queryByRole("button", { name: /delete/i })).toBeNull();
    });
    expect(screen.getByDisplayValue("Shopify Tee")).toBeDisabled();
    expect(screen.queryByRole("heading", { name: /^media$/i })).toBeNull();
  });
});
