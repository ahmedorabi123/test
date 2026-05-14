import { test, expect } from "@playwright/test";
import { loginAsAdmin } from "./helpers";

test.describe("Users and roles", () => {
  test("admin can open the roles tab", async ({ page }) => {
    await loginAsAdmin(page);
    await page.goto("/users");

    await expect(
      page.getByRole("heading", { name: /users & roles/i }),
    ).toBeVisible();

    await page.getByRole("tab", { name: "Roles" }).click();
    await expect(page.getByRole("button", { name: /new role/i })).toBeVisible();
  });
});
