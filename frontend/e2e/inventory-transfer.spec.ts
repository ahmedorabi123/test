import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

/**
 * Inventory transfers E2E (lightweight — relies on seeded warehouses).
 *
 * Verifies that:
 *   1. Admin can open the Transfer modal from /inventory and the dialog renders.
 *   2. The Transfer history page (/inventory/transfers) is reachable from
 *      the inventory dashboard.
 *
 * Posting a real transfer requires seeded variants + stock_items, which is
 * already exercised by spec/requests/api/v1/stock_transfers_spec.rb.
 */
test.describe("Inventory transfers", () => {
  test("admin can open the Transfer dialog from /inventory", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/inventory");

    await page.getByRole("button", { name: /^transfer$/i }).first().click();
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(
      dialog.getByRole("heading", { name: /transfer stock/i }),
    ).toBeVisible();
    // The new batch UI surfaces either an "Add line" button (when eligible
    // warehouses exist) or the explicit guard message (when they do not).
    const addLine = dialog.getByRole("button", { name: /add line/i });
    const guard = dialog.getByText(
      /At least two non-Shopify warehouses are required/i,
    );
    await expect(addLine.or(guard)).toBeVisible();
  });

  test("transfer history page is reachable", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/inventory/transfers");
    await expect(
      page.getByRole("heading", { name: /transfer/i }).first(),
    ).toBeVisible({ timeout: 10_000 });
  });
});
