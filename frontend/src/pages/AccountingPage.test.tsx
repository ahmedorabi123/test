import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import AccountingPage from "./AccountingPage";

const ACCOUNTS = [
  {
    id: "a-1",
    code: "1000",
    name: "Cash",
    account_type: "asset",
    normal_side: "debit",
    currency: "USD",
    active: true,
  },
  {
    id: "a-2",
    code: "1100",
    name: "Accounts Receivable",
    account_type: "asset",
    normal_side: "debit",
    currency: "USD",
    active: true,
  },
];

function mockBaseEndpoints() {
  server.use(
    http.get("*/api/v1/accounting/accounts", () =>
      HttpResponse.json({ data: ACCOUNTS }),
    ),
    http.get("*/api/v1/accounting/journal_entries", () =>
      HttpResponse.json({
        data: [
          {
            id: "je-1",
            entry_date: "2026-04-01",
            description: "Opening balance",
            status: "posted",
            currency: "USD",
            entry_type: "manual",
            total_debits: 100,
            total_credits: 100,
            created_at: "2026-04-01T10:00:00Z",
          },
        ],
        meta: { page: 1, per_page: 25, total: 1 },
      }),
    ),
  );
}

describe("AccountingPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("renders the heading and default journal tab", async () => {
    mockBaseEndpoints();
    renderWithProviders(<AccountingPage />, { route: "/accounting" });
    expect(
      screen.getByRole("heading", { name: "Accounting" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getAllByText("Opening balance").length).toBeGreaterThan(0),
    );
  });

  it("switches to the Chart of Accounts tab and shows sorted accounts", async () => {
    mockBaseEndpoints();
    renderWithProviders(<AccountingPage />, { route: "/accounting" });
    await userEvent.click(
      screen.getByRole("tab", { name: /Chart of Accounts/i }),
    );
    await waitFor(() => {
      // Both account names appear
      expect(screen.getAllByText("Cash").length).toBeGreaterThan(0);
      expect(screen.getAllByText("Accounts Receivable").length).toBeGreaterThan(
        0,
      );
    });
  });

  it("changes per_page on the journal tab", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/accounting/accounts", () =>
        HttpResponse.json({ data: ACCOUNTS }),
      ),
      http.get("*/api/v1/accounting/journal_entries", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 25, total: 0 },
        });
      }),
    );
    renderWithProviders(<AccountingPage />, { route: "/accounting" });

    await waitFor(() => expect(lastUrl).toMatch(/per_page=25/));

    const perPageSelect = screen.getByLabelText(/Per page/i);
    await userEvent.selectOptions(perPageSelect, "100");

    await waitFor(() => {
      expect(lastUrl).toMatch(/per_page=100/);
    });
  });

  it("sends sort=description when clicking the Description header", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/accounting/accounts", () =>
        HttpResponse.json({ data: ACCOUNTS }),
      ),
      http.get("*/api/v1/accounting/journal_entries", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 25, total: 0 },
        });
      }),
    );
    renderWithProviders(<AccountingPage />, { route: "/accounting" });
    await waitFor(() => expect(lastUrl).toMatch(/sort=entry_date/));

    const descHeader = screen.getByText("Description");
    await userEvent.click(descHeader);

    await waitFor(() => {
      expect(lastUrl).toMatch(/sort=description/);
    });
  });

  it("removes the salaries tab", () => {
    mockBaseEndpoints();
    renderWithProviders(<AccountingPage />, { route: "/accounting" });

    expect(
      screen.queryByRole("tab", { name: /salaries/i }),
    ).not.toBeInTheDocument();
  });

  it("defaults manual entries to EGP and searches accounts by q", async () => {
    let accountsUrl = "";
    let suppliersUrl = "";
    server.use(
      http.get("*/api/v1/accounting/accounts", ({ request }) => {
        accountsUrl = request.url;
        return HttpResponse.json({ data: ACCOUNTS });
      }),
      http.get("*/api/v1/accounting/journal_entries", () =>
        HttpResponse.json({
          data: [],
          meta: { page: 1, per_page: 25, total: 0 },
        }),
      ),
      http.get("*/api/v1/suppliers", ({ request }) => {
        suppliersUrl = request.url;
        return HttpResponse.json({
          data: [
            {
              id: "sup-1",
              supplier_code: "MAT-1",
              name: "Fabric Co",
              kind: "material",
              email: null,
              phone: null,
              currency: "EGP",
              status: "active",
              created_at: "2026-04-01T10:00:00Z",
              updated_at: "2026-04-01T10:00:00Z",
            },
          ],
          meta: { page: 1, per_page: 200, total: 1 },
        });
      }),
    );

    renderWithProviders(<AccountingPage />, { route: "/accounting" });
    await userEvent.click(screen.getByRole("tab", { name: /manual entry/i }));

    expect(await screen.findByDisplayValue("EGP")).toBeInTheDocument();
    await waitFor(() => {
      expect(new URL(suppliersUrl).searchParams.get("kind")).toBe("material");
    });
    expect(await screen.findAllByText(/MAT-1 - Fabric Co/i)).not.toHaveLength(
      0,
    );

    await userEvent.type(
      screen.getByPlaceholderText(/filter accounts by code or name/i),
      "cash",
    );

    await waitFor(() => {
      expect(new URL(accountsUrl).searchParams.get("q")).toBe("cash");
    });
  });
});
