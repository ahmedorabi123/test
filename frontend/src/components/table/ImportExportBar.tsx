import { useRef, useState } from "react";
import api from "../../api/client";

export type ExportFormat = "csv" | "json" | "xlsx";

export interface ImportExportBarProps {
  /** Backend resource path, e.g. "products", "customers". */
  resource: string;
  /** Extra query params to forward on export (filters, sort, etc). */
  exportParams?: Record<string, string | number | undefined>;
  /** Extra query params to forward on import (e.g. mode=showroom). */
  importParams?: Record<string, string | number | undefined>;
  /** File picker accept attribute. Default: csv only. */
  importAccept?: string;
  /** Optional helper text inside the import modal. */
  importHelpText?: string;
  /** Which formats to offer. Default: csv, json, xlsx. */
  formats?: ExportFormat[];
  /** Enable import UI. Default: true. */
  allowImport?: boolean;
  /** Called after successful import commit. */
  onImported?: (result: {
    created: number;
    updated: number;
    errors: ImportErrorRow[];
  }) => void;
}

interface ImportErrorRow {
  row?: number;
  message?: string;
}

interface ImportPreview {
  total?: number;
  valid?: number;
  errors?: ImportErrorRow[];
  warnings?: unknown[];
  sample?: unknown[];
}

interface ApiError {
  response?: { data?: { error?: { detail?: string } | string } };
  message?: string;
}

function apiErrorDetail(err: unknown, fallback: string) {
  const error = err as ApiError;
  const payload = error.response?.data?.error;
  if (typeof payload === "string") return payload;
  return payload?.detail || error.message || fallback;
}

export default function ImportExportBar({
  resource,
  exportParams = {},
  importParams = {},
  importAccept = ".csv,text/csv",
  importHelpText,
  formats = ["csv", "json", "xlsx"],
  allowImport = true,
  onImported,
}: ImportExportBarProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleExport(fmt: ExportFormat) {
    setMenuOpen(false);
    const qs = new URLSearchParams();
    Object.entries(exportParams).forEach(([k, v]) => {
      if (v !== undefined && v !== "") qs.append(k, String(v));
    });
    qs.set("format", fmt);
    const res = await api.get(`/${resource}/export?${qs.toString()}`, {
      responseType: "blob",
    });
    const blob = new Blob([res.data]);
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${resource}-${new Date().toISOString().slice(0, 10)}.${fmt}`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  async function handleValidate() {
    if (!file) return;
    setBusy(true);
    setError(null);
    setPreview(null);
    try {
      const form = new FormData();
      form.append("file", file);
      const qs = importQueryString();
      const res = await api.post(`/${resource}/import${qs}`, form, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      setPreview(res.data.data);
    } catch (err: unknown) {
      setError(apiErrorDetail(err, "Import validation failed"));
    } finally {
      setBusy(false);
    }
  }

  async function handleCommit() {
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      const form = new FormData();
      form.append("file", file);
      const qs = importQueryString();
      const res = await api.post(`/${resource}/import/commit${qs}`, form, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      onImported?.(res.data.data);
      setImportOpen(false);
      setFile(null);
      setPreview(null);
    } catch (err: unknown) {
      setError(apiErrorDetail(err, "Import failed"));
    } finally {
      setBusy(false);
    }
  }

  function importQueryString() {
    const qs = new URLSearchParams();
    Object.entries(importParams).forEach(([k, v]) => {
      if (v !== undefined && v !== "") qs.append(k, String(v));
    });
    const s = qs.toString();
    return s ? `?${s}` : "";
  }

  return (
    <div className="flex items-center gap-2 relative">
      {/* Export */}
      <div className="relative">
        <button
          onClick={() => setMenuOpen((v) => !v)}
          className="px-3 py-1.5 text-sm border border-slate-300 rounded-md bg-white hover:bg-slate-50 flex items-center gap-1"
        >
          Export
          <svg className="w-3 h-3" viewBox="0 0 12 12" fill="currentColor">
            <path
              d="M2 4l4 4 4-4"
              stroke="currentColor"
              fill="none"
              strokeWidth="1.5"
            />
          </svg>
        </button>
        {menuOpen && (
          <div
            className="absolute right-0 top-full mt-1 bg-white border border-slate-200 rounded-md shadow-lg z-10 min-w-[120px]"
            onMouseLeave={() => setMenuOpen(false)}
          >
            {formats.map((f) => (
              <button
                key={f}
                onClick={() => handleExport(f)}
                className="block w-full text-left px-3 py-2 text-sm hover:bg-slate-50 uppercase"
              >
                {f}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Import */}
      {allowImport && (
        <button
          onClick={() => setImportOpen(true)}
          className="px-3 py-1.5 text-sm border border-slate-300 rounded-md bg-white hover:bg-slate-50"
        >
          Import
        </button>
      )}

      {/* Import modal */}
      {importOpen && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-2xl max-h-[85vh] overflow-hidden flex flex-col">
            <div className="px-5 py-3 border-b border-slate-200 flex items-center justify-between">
              <h3 className="font-semibold">Import {resource}</h3>
              <button
                onClick={() => {
                  setImportOpen(false);
                  setFile(null);
                  setPreview(null);
                  setError(null);
                }}
                className="text-slate-400 hover:text-slate-700"
              >
                ✕
              </button>
            </div>
            <div className="p-5 overflow-auto flex-1">
              {!preview && (
                <div>
                  <p className="text-sm text-slate-600 mb-3">
                    {importHelpText ??
                      "Upload a CSV file. Column headers should match the Shopify export format. The system will validate every row before committing."}
                  </p>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept={importAccept}
                    onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                    className="block text-sm"
                  />
                  {file && (
                    <div className="mt-2 text-xs text-slate-500">
                      Selected: {file.name} ({Math.round(file.size / 1024)} KB)
                    </div>
                  )}
                </div>
              )}
              {preview && (
                <div>
                  {(() => {
                    const previewErrors = preview.errors ?? [];
                    const previewSample = preview.sample ?? [];

                    return (
                      <>
                        <div className="grid grid-cols-4 gap-3 mb-4 text-sm">
                          <Stat label="Rows" value={preview.total ?? 0} />
                          <Stat
                            label="Valid"
                            value={preview.valid ?? 0}
                            color="green"
                          />
                          <Stat
                            label="Errors"
                            value={previewErrors.length}
                            color="red"
                          />
                          <Stat
                            label="Warnings"
                            value={preview.warnings?.length ?? 0}
                            color="amber"
                          />
                        </div>
                        {previewErrors.length > 0 && (
                          <div className="mb-3 max-h-48 overflow-auto border border-red-200 rounded bg-red-50 p-3 text-xs">
                            <div className="font-semibold text-red-900 mb-1">
                              Errors
                            </div>
                            {previewErrors.slice(0, 20).map((e, i) => (
                              <div key={i} className="text-red-700">
                                Row {e.row}: {e.message}
                              </div>
                            ))}
                          </div>
                        )}
                        {previewSample.length > 0 && (
                          <div className="text-xs text-slate-600">
                            <div className="font-semibold mb-1">
                              Preview (first 5 rows)
                            </div>
                            <pre className="bg-slate-50 p-2 rounded overflow-auto max-h-48">
                              {JSON.stringify(previewSample, null, 2)}
                            </pre>
                          </div>
                        )}
                      </>
                    );
                  })()}
                </div>
              )}
              {error && (
                <div className="mt-3 text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2">
                  {error}
                </div>
              )}
            </div>
            <div className="px-5 py-3 border-t border-slate-200 flex justify-end gap-2 bg-slate-50">
              <button
                onClick={() => {
                  setImportOpen(false);
                  setFile(null);
                  setPreview(null);
                  setError(null);
                }}
                className="px-3 py-1.5 text-sm border border-slate-300 rounded-md bg-white"
              >
                Cancel
              </button>
              {!preview && (
                <button
                  onClick={handleValidate}
                  disabled={!file || busy}
                  className="px-3 py-1.5 text-sm bg-indigo-600 text-white rounded-md disabled:opacity-50"
                >
                  {busy ? "Validating…" : "Validate"}
                </button>
              )}
              {preview && (
                <>
                  <button
                    onClick={() => {
                      setPreview(null);
                    }}
                    className="px-3 py-1.5 text-sm border border-slate-300 rounded-md bg-white"
                  >
                    Back
                  </button>
                  <button
                    onClick={handleCommit}
                    disabled={busy || (preview.errors?.length ?? 0) > 0}
                    className="px-3 py-1.5 text-sm bg-green-600 text-white rounded-md disabled:opacity-50"
                  >
                    {busy ? "Importing…" : `Commit ${preview.valid ?? 0} rows`}
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Stat({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color?: "green" | "red" | "amber";
}) {
  const colorClasses =
    color === "green"
      ? "text-green-700 bg-green-50 border-green-200"
      : color === "red"
        ? "text-red-700 bg-red-50 border-red-200"
        : color === "amber"
          ? "text-amber-700 bg-amber-50 border-amber-200"
          : "text-slate-700 bg-slate-50 border-slate-200";
  return (
    <div className={`border rounded px-3 py-2 ${colorClasses}`}>
      <div className="text-xs uppercase tracking-wider">{label}</div>
      <div className="text-xl font-semibold">{value}</div>
    </div>
  );
}
