import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { server } from "../test/server";
import { renderWithProviders } from "../test/renderWithProviders";
import { setBreakpoint } from "../test/breakpoint";
import ShipmentsPage from "./ShipmentsPage";

describe("ShipmentsPage", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("uses only delivery_status=failed for the Failed chip", async () => {
    let lastUrl = "";
    server.use(
      http.get("*/api/v1/fulfillments", ({ request }) => {
        lastUrl = request.url;
        return HttpResponse.json({
          data: [],
          meta: { total: 0, page: 1, per_page: 25 },
        });
      }),
    );

    renderWithProviders(<ShipmentsPage />, { route: "/shipments" });
    await userEvent.click(screen.getByRole("button", { name: /failed/i }));

    await waitFor(() => {
      const params = new URL(lastUrl).searchParams;
      expect(params.get("delivery_status")).toBe("failed");
      expect(params.get("status")).toBeNull();
    });
  });
});
