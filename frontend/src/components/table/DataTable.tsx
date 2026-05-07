import { Fragment, ReactNode, useState, useEffect, useMemo } from "react";
import { useSearchParams } from "react-router-dom";

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
  syncToUrl = true,
}: DataTableProps<T>) {
  const [searchParams, setSearchParams] = useSearchParams();

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

  return (
    <div className="flex flex-col">
      {/* Toolbar / Filters */}
      {toolbar && <div className="mb-3">{toolbar}</div>}

      {/* Bulk action bar */}
      {selectable && selectedRows.length > 0 && bulkActions.length > 0 && (
        <div className="flex items-center gap-3 px-4 py-2 mb-2 bg-indigo-50 border border-indigo-200 rounded-lg">
          <span className="text-sm font-medium text-indigo-900">
            {selectedRows.length} selected
          </span>
          <div className="flex-1" />
          <button
            onClick={() => setSelectedIds(new Set())}
            className="text-sm text-indigo-600 hover:text-indigo-800"
          >
            Clear
          </button>
          {bulkActions.map((a) => (
            <button
              key={a.id}
              onClick={() => runBulk(a)}
              className={`text-sm px-3 py-1.5 rounded-md border ${
                a.destructive
                  ? "bg-white border-red-300 text-red-700 hover:bg-red-50"
                  : "bg-white border-slate-300 text-slate-800 hover:bg-slate-50"
              }`}
            >
              {a.label}
            </button>
          ))}
        </div>
      )}

      {/* Table */}
      <div className="bg-white border border-slate-200 rounded-lg overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 border-b border-slate-200">
              <tr>
                {selectable && (
                  <th className="px-4 py-3 w-10">
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
                {columns.map((col) => {
                  const isSorted = currentSort?.key === col.sortKey;
                  return (
                    <th
                      key={col.id}
                      className={`px-4 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider ${col.headerClassName ?? ""} ${col.sortKey ? "cursor-pointer select-none hover:bg-slate-100" : ""}`}
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
                        {columns.map((col) => (
                          <td
                            key={col.id}
                            className={`px-4 py-3 text-slate-700 ${col.className ?? ""}`}
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
        </div>

        {/* Pagination */}
        {(onPageChange || onPerPageChange) && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-slate-200 bg-slate-50 text-sm text-slate-600">
            <div>
              Showing <span className="font-medium">{showingStart}</span>–
              <span className="font-medium">{showingEnd}</span> of{" "}
              <span className="font-medium">{totalRows}</span>
            </div>
            <div className="flex items-center gap-3">
              {onPerPageChange && (
                <label className="flex items-center gap-2">
                  <span className="text-xs text-slate-500">Per page</span>
                  <select
                    value={perPage}
                    onChange={(e) => onPerPageChange(Number(e.target.value))}
                    className="border border-slate-300 rounded px-2 py-1 text-sm"
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
                    className="px-2 py-1 border border-slate-300 rounded disabled:opacity-40"
                  >
                    ‹ Prev
                  </button>
                  <span>
                    Page <span className="font-medium">{page}</span> of{" "}
                    {totalPages}
                  </span>
                  <button
                    onClick={() => onPageChange(Math.min(totalPages, page + 1))}
                    disabled={page >= totalPages}
                    className="px-2 py-1 border border-slate-300 rounded disabled:opacity-40"
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
