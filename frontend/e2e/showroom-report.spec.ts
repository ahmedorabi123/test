import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

/**
 * Showroom report E2E (lightweight).
 *
 * Verifies:
 *   1. Admin can open the Showroom report dialog from /inventory.
 *   2. The quantity input accepts negative values (signed-qty UI for
 *      accounting-only sales reversals).
 *
 * Deeper assertions (positive vs negative branches, journal posting,
 * idempotency) are covered by:
 *   - spec/requests/api/v1/showroom_sales_spec.rb
 *   - spec/domains/sales/showroom_sales_report_poster_spec.rb
 */
test.describe("Showroom report dialog", () => {
  test("opens and exposes a signed quantity input", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/inventory");

    await page
      .getByRole("button", { name: /showroom report/i })
      .first()
      .click();

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(/post showroom sales report/i)).toBeVisible();

    const qty = dialog.getByLabel(/quantity/i).first();
    await qty.fill("-1");
    await expect(qty).toHaveValue("-1");
  });
});
