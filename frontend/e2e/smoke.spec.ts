import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

test.describe("Smoke: authenticated navigation", () => {
  test("logs in and navigates Orders → Refunds → Shipments → Inventory", async ({ page }) => {
    await loginAsAdmin(page);

    await page.goto("/orders");
    await expect(page.getByRole("heading", { name: /^orders$/i, level: 1 })).toBeVisible();

    await page.goto("/refunds");
    await expect(page.getByRole("heading", { name: /refunds/i, level: 1 })).toBeVisible();

    await page.goto("/shipments");
    await expect(page.getByRole("heading", { name: /shipments/i, level: 1 })).toBeVisible();

    await page.goto("/inventory");
    await expect(page.getByRole("heading", { name: /inventory/i, level: 1 })).toBeVisible();
  });
});
