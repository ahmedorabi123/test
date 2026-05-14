import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import AuditLogsPage from "./AuditLogsPage";

const SAMPLE_LOG = {
  id: "log-1",
  action: "customer.create",
  subject_type: "Customer",
  subject_id: "c-abcdef-12",
  user: { id: "u-1", email: "admin@example.com" },
  ip_address: "127.0.0.1",
  user_agent: "vitest",
  diff: { name: ["Old", "New"] },
  occurred_at: "2026-04-01T10:00:00Z",
};

describe("AuditLogsPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("renders entries from the API", async () => {
    server.use(
      http.get("*/api/v1/audit_logs", () =>
        HttpResponse.json({
          data: [SAMPLE_LOG],
          meta: { page: 1, per_page: 50, total: 1 },
        }),
      ),
    );
    renderWithProviders(<AuditLogsPage />, { route: "/audit-logs" });
    await waitFor(() => {
      expect(screen.getAllByText("customer.create").length).toBeGreaterThan(0);
    });
    expect(screen.getByText(/admin only/i)).toBeInTheDocument();
  });

  it("renders a permission error when API returns 403", async () => {
    server.use(
      http.get("*/api/v1/audit_logs", () =>
        HttpResponse.json({ error: "forbidden" }, { status: 403 }),
      ),
    );
    renderWithProviders(<AuditLogsPage />, { route: "/audit-logs" });
    await waitFor(() => {
      expect(screen.getByText(/don't have permission/i)).toBeInTheDocument();
    });
  });

  it("uses default per_page=50 and lets user change it to 25", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/audit_logs", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [SAMPLE_LOG],
          meta: { page: 1, per_page: 50, total: 1 },
        });
      }),
    );
    renderWithProviders(<AuditLogsPage />, { route: "/audit-logs" });
    await waitFor(() => {
      expect(lastUrl).toMatch(/per_page=50/);
    });

    const perPageSelect = screen.getByLabelText(/Per page/i);
    await userEvent.selectOptions(perPageSelect, "25");

    await waitFor(() => {
      expect(lastUrl).toMatch(/per_page=25/);
    });
  });

  it("filters by action_type via the action input", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/audit_logs", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 50, total: 0 },
        });
      }),
    );
    renderWithProviders(<AuditLogsPage />, { route: "/audit-logs" });
    const input = screen.getByPlaceholderText(
      /Action \(e\.g\. customer\.create\)/i,
    );
    await userEvent.type(input, "order.create");

    await waitFor(() => {
      expect(lastUrl).toMatch(/action_type=order\.create/);
    });
  });

  it("sends q, actor_email and date filters", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/audit_logs", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 50, total: 0 },
        });
      }),
    );

    renderWithProviders(<AuditLogsPage />, { route: "/audit-logs" });
    await userEvent.type(screen.getByTestId("audit-q"), "supplier");
    await userEvent.type(
      screen.getByTestId("audit-actor-email"),
      "ADMIN@ERP.LOCAL",
    );
    await userEvent.type(screen.getByTestId("audit-from-date"), "2026-05-01");
    await userEvent.type(screen.getByTestId("audit-to-date"), "2026-05-31");

    await waitFor(() => {
      const params = new URL(lastUrl).searchParams;
      expect(params.get("q")).toBe("supplier");
      expect(params.get("actor_email")).toBe("ADMIN@ERP.LOCAL");
      expect(params.get("from_date")).toBe("2026-05-01");
      expect(params.get("to_date")).toBe("2026-05-31");
    });
  });
});
