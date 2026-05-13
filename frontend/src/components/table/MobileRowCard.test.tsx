import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { MobileRowCard } from "./MobileRowCard";

describe("MobileRowCard", () => {
  it("renders title, subtitle, meta and field list", () => {
    render(
      <MobileRowCard
        title="SO-0001"
        subtitle="jane@example.com"
        meta="$199.99"
        fields={[
          { label: "Status", value: "paid" },
          { label: "Items", value: 3 },
        ]}
      />,
    );
    expect(screen.getByText("SO-0001")).toBeInTheDocument();
    expect(screen.getByText("jane@example.com")).toBeInTheDocument();
    expect(screen.getByText("$199.99")).toBeInTheDocument();
    expect(screen.getByText("Status")).toBeInTheDocument();
    expect(screen.getByText("paid")).toBeInTheDocument();
    expect(screen.getByText("Items")).toBeInTheDocument();
    expect(screen.getByText("3")).toBeInTheDocument();
  });

  it("renders custom actions", () => {
    render(<MobileRowCard title="x" actions={<button>open</button>} />);
    expect(screen.getByRole("button", { name: "open" })).toBeInTheDocument();
  });
});
