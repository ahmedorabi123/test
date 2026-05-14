import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import UsersPage from "./UsersPage";

describe("UsersPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("renders users returned by the API", async () => {
    server.use(
      http.get("*/api/v1/users", () =>
        HttpResponse.json({
          data: [
            {
              id: "u-1",
              email: "admin@erp.local",
              first_name: "Admin",
              last_name: "User",
              active: true,
              roles: ["admin"],
              created_at: "2026-04-01T10:00:00Z",
              updated_at: "2026-04-01T10:00:00Z",
            },
          ],
          meta: { page: 1, per_page: 25, total: 1 },
        }),
      ),
      http.get("*/api/v1/roles", () => HttpResponse.json({ data: [] })),
    );

    renderWithProviders(<UsersPage />, { route: "/users" });

    expect(
      screen.getByRole("heading", { name: /users & roles/i }),
    ).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getAllByText("admin@erp.local").length).toBeGreaterThan(0);
    });
  });
});
