import { Fragment, ReactNode, useState, useEffect, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { useBreakpoint } from "../../hooks/useBreakpoint";
import { Card, CardBody } from "../ui/Card";

export type SortDir = "asc" | "desc";

export interface Column<T> {
  /** Unique id used for sort param. */
  id: string;
  header: string;
  /** Accessor used for rendering. */
  render: (row: T) => ReactNode;
  /** If provided, column is sortable — this is the backend sort key. */
  sortKey?: string;
  className?: string;
  headerClassName?: string;
}

export interface BulkAction<T> {
  id: string;
  label: string;
  /** Optional icon path (d attr of svg). */
  iconPath?: string;
  destructive?: boolean;
  /** Return true to clear selection after. Default: true */
  run: (selectedRows: T[]) => Promise<boolean | void> | boolean | void;
}

export interface DataTableProps<T extends { id: string | number }> {
  rows: T[];
  columns: Column<T>[];
  loading?: boolean;
  error?: string | null;
  emptyMessage?: string;
  /** Total rows (for pagination). */
  total?: number;
  page?: number;
  perPage?: number;
  onPageChange?: (page: number) => void;
  onPerPageChange?: (perPage: number) => void;
  /** Current sort — if absent, reads from URL `?sort=&dir=`. */
  sort?: { key: string; dir: SortDir } | null;
  onSortChange?: (sort: { key: string; dir: SortDir }) => void;
  /** Multi-select. */
  selectable?: boolean;
  bulkActions?: BulkAction<T>[];
  /** Optional row click handler (does not toggle selection). */
  onRowClick?: (row: T) => void;
  /** Optional expanded row renderer. Row click toggles expansion when present. */
  renderExpanded?: (row: T) => ReactNode;
  /** Render an extra toolbar area (e.g., filters, export bar). */
  toolbar?: ReactNode;
  /** Mobile-first row renderer for data-heavy list pages. */
  mobileCardRenderer?: (
    row: T,
    context: {
      checked: boolean;
      expanded: boolean;
      toggleSelected: () => void;
      toggleExpanded: () => void;
    },
  ) => ReactNode;
  /** Sync sort to URL params. Default true. */
  syncToUrl?: boolean;
}

const PAGE_SIZES = [10, 25, 50, 100];

export default function DataTable<T extends { id: string | number }>({
  rows,
  columns,
  loading = false,
  error = null,
  emptyMessage = "No records found.",
  total,
  page = 1,
  perPage = 25,
  onPageChange,
  onPerPageChange,
  sort: sortProp,
  onSortChange,
  selectable = false,
  bulkActions = [],
  onRowClick,
  renderExpanded,
  toolbar,
  mobileCardRenderer,
  syncToUrl = true,
}: DataTableProps<T>) {
  const [searchParams, setSearchParams] = useSearchParams();
  const breakpoint = useBreakpoint();

  // Sort state: either controlled via prop, or synced from URL.
  const urlSort = syncToUrl
    ? (() => {
        const key = searchParams.get("sort");
        const dir = searchParams.get("dir") as SortDir | null;
        return key && (dir === "asc" || dir === "desc") ? { key, dir } : null;
      })()
    : null;
  const currentSort = sortProp !== undefined ? sortProp : urlSort;

  function handleSort(col: Column<T>) {
    if (!col.sortKey) return;
    let next: { key: string; dir: SortDir };
    if (!currentSort || currentSort.key !== col.sortKey) {
      // First click on this column: sort ascending
      next = { key: col.sortKey, dir: "asc" };
    } else if (currentSort.dir === "asc") {
      // Second click: sort descending
      next = { key: col.sortKey, dir: "desc" };
    } else {
      // Third click / already desc: flip back to ascending (Shopify style)
      next = { key: col.sortKey, dir: "asc" };
    }
    if (onSortChange) onSortChange(next);
    if (syncToUrl) {
      const sp = new URLSearchParams(searchParams);
      sp.set("sort", next.key);
      sp.set("dir", next.dir);
      setSearchParams(sp, { replace: true });
    }
  }

  // Selection
  const [selectedIds, setSelectedIds] = useState<Set<string | number>>(
    new Set(),
  );
  // Prune selection when rows change (e.g., page change)
  useEffect(() => {
    setSelectedIds((prev) => {
      const rowIds = new Set(rows.map((r) => r.id));
      const next = new Set<string | number>();
      prev.forEach((id) => {
        if (rowIds.has(id)) next.add(id);
      });
      return next;
    });
  }, [rows]);

  const allVisibleSelected =
    rows.length > 0 && rows.every((r) => selectedIds.has(r.id));
  const someVisibleSelected =
    !allVisibleSelected && rows.some((r) => selectedIds.has(r.id));

  function toggleAll() {
    setSelectedIds((prev) => {
      if (allVisibleSelected) {
        const next = new Set(prev);
        rows.forEach((r) => next.delete(r.id));
        return next;
      }
      const next = new Set(prev);
      rows.forEach((r) => next.add(r.id));
      return next;
    });
  }
  function toggleRow(id: string | number) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  const [expandedIds, setExpandedIds] = useState<Set<string | number>>(
    new Set(),
  );
  function toggleExpanded(id: string | number) {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const selectedRows = useMemo(
    () => rows.filter((r) => selectedIds.has(r.id)),
    [rows, selectedIds],
  );

  async function runBulk(action: BulkAction<T>) {
    if (selectedRows.length === 0) return;
    const clear = await action.run(selectedRows);
    if (clear !== false) setSelectedIds(new Set());
  }

  // Pagination math
  const totalRows = total ?? rows.length;
  const totalPages = Math.max(1, Math.ceil(totalRows / perPage));
  const showingStart = totalRows === 0 ? 0 : (page - 1) * perPage + 1;
  const showingEnd = Math.min(page * perPage, totalRows);
  const useMobileCards = breakpoint === "mobile" && Boolean(mobileCardRenderer);

  return (
    <div className="flex flex-col">
      {/* Toolbar / Filters */}
      {toolbar && <div className="mb-3">{toolbar}</div>}

      {/* Bulk action bar */}
      {selectable && selectedRows.length > 0 && bulkActions.length > 0 && (
        <div className="mb-2 flex flex-col gap-3 rounded-lg border border-indigo-200 bg-indigo-50 px-4 py-3 xs:flex-row xs:items-center">
          <span className="text-sm font-medium text-indigo-900">
            {selectedRows.length} selected
          </span>
          <div className="flex flex-1 flex-col gap-2 xs:flex-row xs:flex-wrap xs:justify-end">
            <button
              onClick={() => setSelectedIds(new Set())}
              className="min-h-10 rounded-md px-3 text-sm text-indigo-600 hover:bg-indigo-100 hover:text-indigo-800"
            >
              Clear
            </button>
            {bulkActions.map((a) => (
              <button
                key={a.id}
                onClick={() => runBulk(a)}
                className={`min-h-10 rounded-md border px-3 text-sm ${
                  a.destructive
                    ? "border-red-300 bg-white text-red-700 hover:bg-red-50"
                    : "border-slate-300 bg-white text-slate-800 hover:bg-slate-50"
                }`}
              >
                {a.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white border border-slate-200 rounded-lg overflow-hidden">
        {useMobileCards && (
          <div className="space-y-3 bg-slate-50 p-3">
            {loading && (
              <Card>
                <CardBody className="py-8 text-center text-slate-500">
                  Loading…
                </CardBody>
              </Card>
            )}
            {!loading && error && (
              <Card>
                <CardBody className="py-8 text-center text-red-600">
                  {error}
                </CardBody>
              </Card>
            )}
            {!loading && !error && rows.length === 0 && (
              <Card>
                <CardBody className="py-8 text-center text-slate-500">
                  {emptyMessage}
                </CardBody>
              </Card>
            )}
            {!loading &&
              !error &&
              rows.map((row) => {
                const checked = selectedIds.has(row.id);
                const expanded = expandedIds.has(row.id);
                return (
                  <Fragment key={row.id}>
                    {mobileCardRenderer?.(row, {
                      checked,
                      expanded,
                      toggleSelected: () => toggleRow(row.id),
                      toggleExpanded: () => toggleExpanded(row.id),
                    })}
                    {renderExpanded && expanded && (
                      <Card>
                        <CardBody>{renderExpanded(row)}</CardBody>
                      </Card>
                    )}
                  </Fragment>
                );
              })}
          </div>
        )}
        {!useMobileCards && <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 border-b border-slate-200">
              <tr>
                {selectable && (
                  <th className="w-10 px-4 py-3">
                    <input
                      type="checkbox"
                      checked={allVisibleSelected}
                      ref={(el) => {
                        if (el) el.indeterminate = someVisibleSelected;
                      }}
                      onChange={toggleAll}
                      className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                      aria-label="Select all visible rows"
                    />
                  </th>
                )}
                {columns.map((col, index) => {
                  const isSorted = currentSort?.key === col.sortKey;
                  return (
                    <th
                      key={col.id}
                      className={`px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider ${!selectable && index === 0 ? "sticky-col bg-slate-50" : ""} ${col.headerClassName ?? ""} ${col.sortKey ? "cursor-pointer select-none hover:bg-slate-100" : ""}`}
                      onClick={() => handleSort(col)}
                    >
                      <span className="inline-flex items-center gap-1">
                        {col.header}
                        {col.sortKey && (
                          <span
                            className={`text-xs ${isSorted ? "text-indigo-600" : "text-slate-300"}`}
                          >
                            {isSorted
                              ? currentSort!.dir === "asc"
                                ? "▲"
                                : "▼"
                              : "↕"}
                          </span>
                        )}
                      </span>
                    </th>
                  );
                })}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading && (
                <tr>
                  <td
                    colSpan={columns.length + (selectable ? 1 : 0)}
                    className="px-4 py-8 text-center text-slate-500"
                  >
                    Loading…
                  </td>
                </tr>
              )}
              {!loading && error && (
                <tr>
                  <td
                    colSpan={columns.length + (selectable ? 1 : 0)}
                    className="px-4 py-8 text-center text-red-600"
                  >
                    {error}
                  </td>
                </tr>
              )}
              {!loading && !error && rows.length === 0 && (
                <tr>
                  <td
                    colSpan={columns.length + (selectable ? 1 : 0)}
                    className="px-4 py-8 text-center text-slate-500"
                  >
                    {emptyMessage}
                  </td>
                </tr>
              )}
              {!loading &&
                !error &&
                rows.map((row) => {
                  const checked = selectedIds.has(row.id);
                  const expanded = expandedIds.has(row.id);
                  return (
                    <Fragment key={row.id}>
                      <tr
                        className={`${onRowClick || renderExpanded ? "cursor-pointer" : ""} ${checked ? "bg-indigo-50/40" : "hover:bg-slate-50"}`}
                        onClick={(e) => {
                          const tag = (e.target as HTMLElement).tagName;
                          if (["A", "BUTTON", "INPUT", "SELECT"].includes(tag))
                            return;
                          if (onRowClick) onRowClick(row);
                          else if (renderExpanded) toggleExpanded(row.id);
                        }}
                      >
                        {selectable && (
                          <td className="px-4 py-3">
                            <input
                              type="checkbox"
                              checked={checked}
                              onChange={() => toggleRow(row.id)}
                              onClick={(e) => e.stopPropagation()}
                              className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                              aria-label={`Select row ${row.id}`}
                            />
                          </td>
                        )}
                        {columns.map((col, index) => (
                          <td
                            key={col.id}
                            className={`px-4 py-3 text-slate-700 ${!selectable && index === 0 ? "sticky-col bg-inherit" : ""} ${col.className ?? ""}`}
                          >
                            {col.render(row)}
                          </td>
                        ))}
                      </tr>
                      {renderExpanded && expanded && (
                        <tr className="bg-slate-50/70">
                          <td
                            colSpan={columns.length + (selectable ? 1 : 0)}
                            className="px-4 py-4"
                          >
                            {renderExpanded(row)}
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
            </tbody>
          </table>
        </div>}

        {/* Pagination */}
        {(onPageChange || onPerPageChange) && (
          <div className="flex flex-col gap-3 border-t border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600 sm:flex-row sm:items-center sm:justify-between">
            <div>
              Showing <span className="font-medium">{showingStart}</span>–
              <span className="font-medium">{showingEnd}</span> of{" "}
              <span className="font-medium">{totalRows}</span>
            </div>
            <div className="flex flex-col gap-2 xs:flex-row xs:flex-wrap xs:items-center xs:justify-end">
              {onPerPageChange && (
                <label className="flex items-center gap-2">
                  <span className="text-xs text-slate-500">Per page</span>
                  <select
                    value={perPage}
                    onChange={(e) => onPerPageChange(Number(e.target.value))}
                    className="min-h-10 rounded border border-slate-300 px-2 text-sm"
                  >
                    {PAGE_SIZES.map((n) => (
                      <option key={n} value={n}>
                        {n}
                      </option>
                    ))}
                  </select>
                </label>
              )}
              {onPageChange && (
                <>
                  <button
                    onClick={() => onPageChange(Math.max(1, page - 1))}
                    disabled={page <= 1}
                    className="min-h-10 rounded border border-slate-300 px-3 disabled:opacity-40"
                  >
                    ‹ Prev
                  </button>
                  <span className="flex min-h-10 items-center justify-center px-2">
                    Page <span className="font-medium">{page}</span> of{" "}
                    {totalPages}
                  </span>
                  <button
                    onClick={() => onPageChange(Math.min(totalPages, page + 1))}
                    disabled={page >= totalPages}
                    className="min-h-10 rounded border border-slate-300 px-3 disabled:opacity-40"
                  >
                    Next ›
                  </button>
                </>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
