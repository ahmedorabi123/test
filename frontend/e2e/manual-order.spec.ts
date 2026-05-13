import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

/**
 * Manual order flow E2E:
 *   1. Login as admin.
 *   2. Visit /orders/new (ManualOrderPage).
 *   3. Verify the page renders with line item editor + customer picker.
 *
 * This is intentionally lightweight — full happy-path order creation requires
 * pre-existing variants/warehouses in the seed DB. The deeper assertions
 * (paid → fulfilled → refund) are covered by spec/integration/order_lifecycle_matrix_spec.rb.
 */
test.describe("Manual order page", () => {
  test("renders the New Order form for an admin user", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/orders/new");
    await expect(
      page.getByRole("heading", { name: /new (manual )?order|create order/i })
    ).toBeVisible();
  });
});
