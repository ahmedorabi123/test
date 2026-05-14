import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright E2E config for shopify_erp_2.
 *
 * Run the backend stack first (docker compose -f backend/docker-compose.yml up -d).
 * Then either run `npm run dev` in another shell, or rely on the webServer
 * block below to spin Vite up automatically.
 *
 * Env:
 *   PLAYWRIGHT_BASE_URL  default http://localhost:5173
 *   E2E_ADMIN_EMAIL      seeded admin email (default admin@example.com)
 *   E2E_ADMIN_PASSWORD   seeded admin password (default password)
 */
export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:5173",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: process.env.E2E_NO_WEBSERVER
    ? undefined
    : {
        command: "npm run dev -- --host 127.0.0.1",
        env: {
          ...process.env,
          VITE_API_URL: process.env.VITE_API_URL || "http://localhost:3010",
        },
        port: 5173,
        reuseExistingServer: true,
        timeout: 60_000,
      },
});
