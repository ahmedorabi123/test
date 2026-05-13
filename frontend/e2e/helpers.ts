import { expect, type Page } from "@playwright/test";

const ADMIN_EMAIL = process.env.E2E_ADMIN_EMAIL || "admin@erp.local";
const ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD || "changeme123!";

export async function loginAsAdmin(page: Page) {
  await page.goto("/login");
  await page.getByPlaceholder("you@example.com").fill(ADMIN_EMAIL);
  await page.locator('input[type="password"]').fill(ADMIN_PASSWORD);
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await expect(page).toHaveURL(/\/$|\/(dashboard|orders|inventory)/, {
    timeout: 10_000,
  });
}