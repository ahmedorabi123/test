import { test, expect, type Page } from "@playwright/test";

const ADMIN_EMAIL = process.env.E2E_ADMIN_EMAIL || "admin@example.com";
const ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD || "password";

export async function loginAsAdmin(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill(ADMIN_EMAIL);
  await page.getByLabel(/password/i).fill(ADMIN_PASSWORD);
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  // Wait until we land somewhere that proves we're authenticated.
  await expect(page).toHaveURL(/\/(dashboard|orders|inventory)/, { timeout: 10_000 });
}

test.describe("Smoke: authenticated navigation", () => {
  test("logs in and navigates Orders → Refunds → Shipments → Inventory", async ({ page }) => {
    await loginAsAdmin(page);

    await page.goto("/orders");
    await expect(page.getByRole("heading", { name: /^orders$/i })).toBeVisible();

    await page.goto("/refunds");
    await expect(page.getByRole("heading", { name: /refunds/i })).toBeVisible();

    await page.goto("/shipments");
    await expect(page.getByRole("heading", { name: /shipments/i })).toBeVisible();

    await page.goto("/inventory");
    await expect(page.getByRole("heading", { name: /inventory/i })).toBeVisible();
  });
});
