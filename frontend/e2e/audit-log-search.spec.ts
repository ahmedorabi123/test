import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

test.describe("Audit log search", () => {
  test("updates the URL with expanded filters", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/audit_logs");

    await expect(
      page.getByRole("heading", { name: /audit logs/i }),
    ).toBeVisible();

    await page.getByTestId("audit-q").fill("supplier");
    await page.getByTestId("audit-actor-email").fill("admin@erp.local");
    await page.getByTestId("audit-from-date").fill("2026-05-01");
    await page.getByTestId("audit-to-date").fill("2026-05-31");

    await expect(page).toHaveURL(/q=supplier/);
    await expect(page).toHaveURL(/actor_email=admin%40erp\.local/);
    await expect(page).toHaveURL(/from_date=2026-05-01/);
    await expect(page).toHaveURL(/to_date=2026-05-31/);
  });
});
