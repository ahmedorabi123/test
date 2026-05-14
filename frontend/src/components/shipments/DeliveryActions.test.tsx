import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import DeliveryActions from "./DeliveryActions";
import type { Fulfillment } from "../../api/fulfillments";

function fulfillment(overrides: Partial<Fulfillment> = {}): Fulfillment {
  return {
    id: "ful-1",
    order_id: "ord-1",
    status: "success",
    tracking_company: "Bosta",
    tracking_number: "BST-1",
    tracking_url: null,
    carrier: "Bosta",
    delivery_status: "pending",
    notes: null,
    tags: [],
    shipped_at: null,
    delivered_at: null,
    location_id: null,
    shopify_fulfillment_id: null,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

describe("DeliveryActions", () => {
  it("hides delivery transition buttons for Shopify-origin fulfillments", () => {
    render(
      <DeliveryActions
        fulfillment={fulfillment({
          read_only_origin: true,
          shopify_fulfillment_id: 123,
        })}
        onUpdated={vi.fn()}
      />,
    );

    expect(
      screen.queryByRole("button", { name: /mark in transit/i }),
    ).not.toBeInTheDocument();
    expect(screen.getByText("pending")).toBeInTheDocument();
  });

  it("hides delivery transition buttons when the parent order is Shopify-origin", () => {
    render(
      <DeliveryActions
        fulfillment={fulfillment({
          order: {
            id: "ord-1",
            order_number: "SO-1",
            source: "shopify",
            status: "processing",
            financial_status: "paid",
            total_price: "100.00",
            currency: "EGP",
            shopify_order_id: 98765,
            read_only_origin: true,
          },
        })}
        onUpdated={vi.fn()}
      />,
    );

    expect(
      screen.queryByRole("button", { name: /mark in transit/i }),
    ).not.toBeInTheDocument();
  });
});
