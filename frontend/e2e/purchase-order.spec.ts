import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

test.describe("Purchase order flow", () => {
  test("new PO form is inventory-only in Phase 1", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/purchases/new");

    await expect(
      page.getByRole("heading", { name: /new purchase order/i }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: /create purchase order/i }),
    ).toBeVisible();
    await expect(page.getByText(/unit cost/i)).toHaveCount(0);
    await expect(page.getByText(/subtotal/i)).toHaveCount(0);
  });
});
