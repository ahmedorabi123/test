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
  it("keeps delivery transition buttons available for Shopify-origin fulfillments", () => {
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
      screen.getByRole("button", { name: /mark in transit/i }),
    ).toBeInTheDocument();
  });
});
