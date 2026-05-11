import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { setBreakpoint } from "../../test/breakpoint";
import DataTable, { type Column } from "./DataTable";

interface Row {
  id: string;
  name: string;
  total: number;
}

const ROWS: Row[] = [
  { id: "1", name: "Alpha", total: 100 },
  { id: "2", name: "Bravo", total: 200 },
];

const COLUMNS: Column<Row>[] = [
  { id: "name", header: "Name", sortKey: "name", render: (r) => r.name },
  { id: "total", header: "Total", sortKey: "total", render: (r) => r.total },
];

function wrap(ui: React.ReactNode) {
  return <MemoryRouter>{ui}</MemoryRouter>;
}

describe("DataTable", () => {
  beforeEach(() => setBreakpoint("desktop"));

  it("renders rows", () => {
    render(
      wrap(<DataTable rows={ROWS} columns={COLUMNS} syncToUrl={false} />)
    );
    expect(screen.getByText("Alpha")).toBeInTheDocument();
    expect(screen.getByText("Bravo")).toBeInTheDocument();
  });

  it("renders the empty message when no rows", () => {
    render(
      wrap(
        <DataTable
          rows={[]}
          columns={COLUMNS}
          emptyMessage="Nothing here"
          syncToUrl={false}
        />
      )
    );
    expect(screen.getByText("Nothing here")).toBeInTheDocument();
  });

  it("toggles sort direction on header click", async () => {
    const onSortChange = vi.fn();
    render(
      wrap(
        <DataTable
          rows={ROWS}
          columns={COLUMNS}
          sort={null}
          onSortChange={onSortChange}
          syncToUrl={false}
        />
      )
    );
    await userEvent.click(screen.getByText("Name"));
    expect(onSortChange).toHaveBeenLastCalledWith({ key: "name", dir: "asc" });
  });

  it("flips to desc on a second click on the same sorted column", async () => {
    const onSortChange = vi.fn();
    render(
      wrap(
        <DataTable
          rows={ROWS}
          columns={COLUMNS}
          sort={{ key: "name", dir: "asc" }}
          onSortChange={onSortChange}
          syncToUrl={false}
        />
      )
    );
    await userEvent.click(screen.getByText("Name"));
    expect(onSortChange).toHaveBeenLastCalledWith({ key: "name", dir: "desc" });
  });

  it("renders pagination controls and reports current state", () => {
    render(
      wrap(
        <DataTable
          rows={ROWS}
          columns={COLUMNS}
          total={50}
          page={2}
          perPage={25}
          onPageChange={() => undefined}
          onPerPageChange={() => undefined}
          syncToUrl={false}
        />
      )
    );
    // Page indicator renders as fragmented text; find the span with the page number
    const pageNumbers = screen.getAllByText("2");
    expect(pageNumbers.length).toBeGreaterThan(0);
    // "Per page" label is present for selector
    expect(screen.getByText(/Per page/i)).toBeInTheDocument();
  });

  it("invokes bulk actions on selected rows", async () => {
    const runFn = vi.fn();
    render(
      wrap(
        <DataTable
          rows={ROWS}
          columns={COLUMNS}
          selectable
          bulkActions={[{ id: "do", label: "Do thing", run: runFn }]}
          syncToUrl={false}
        />
      )
    );
    // Pick first row checkbox (skip the "select all" header)
    const checkboxes = screen.getAllByRole("checkbox");
    await userEvent.click(checkboxes[1]);
    const doButton = await screen.findByRole("button", { name: "Do thing" });
    await userEvent.click(doButton);
    expect(runFn).toHaveBeenCalledTimes(1);
    const selectedArg = runFn.mock.calls[0][0] as Row[];
    expect(selectedArg).toHaveLength(1);
    expect(selectedArg[0].id).toBe("1");
  });

  it("calls onRowClick when row body is clicked", async () => {
    const onRowClick = vi.fn();
    render(
      wrap(
        <DataTable
          rows={ROWS}
          columns={COLUMNS}
          onRowClick={onRowClick}
          syncToUrl={false}
        />
      )
    );
    const alphaCell = screen.getByText("Alpha");
    const row = alphaCell.closest("tr");
    expect(row).toBeTruthy();
    await userEvent.click(within(row as HTMLElement).getByText("Alpha"));
    expect(onRowClick).toHaveBeenCalledWith(ROWS[0]);
  });
});
