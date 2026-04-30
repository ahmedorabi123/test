import { useCallback, useEffect, useState } from "react";
import {
  productionOrdersApi,
  productionStagesApi,
  type ProductionOrder,
  type ProductionStage,
} from "../../api/production";
import { suppliersApi, type Supplier } from "../../api/suppliers";

const STAGE_PRESETS = ["cutting", "sewing", "printing", "qc"];

const STATUS_STYLES: Record<string, string> = {
  pending: "bg-gray-100 text-gray-700 ring-gray-500/20",
  in_progress: "bg-sky-50 text-sky-700 ring-sky-600/20",
  completed: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  skipped: "bg-amber-50 text-amber-700 ring-amber-600/20",
};

export default function StagesDrawer({
  orderId,
  onClose,
  onChanged,
}: {
  orderId: string;
  onClose: () => void;
  onChanged?: () => void;
}) {
  const [po, setPo] = useState<ProductionOrder | null>(null);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Add stage form
  const [newName, setNewName] = useState("cutting");
  const [newSupplierId, setNewSupplierId] = useState<string>("");
  const [newUnitCost, setNewUnitCost] = useState<string>("");
  const [newNotes, setNewNotes] = useState<string>("");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await productionOrdersApi.get(orderId);
      setPo(data);
    } catch (e) {
      setError((e as Error).message || "Failed to load");
    } finally {
      setLoading(false);
    }
  }, [orderId]);

  useEffect(() => {
    load();
    suppliersApi
      .list({ per_page: 200, status: "active" })
      .then((r) => setSuppliers(r.data))
      .catch(() => setSuppliers([]));
  }, [load]);

  const refresh = async () => {
    await load();
    onChanged?.();
  };

  const handle = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await refresh();
    } catch (e) {
      setError((e as Error).message || "Action failed");
    } finally {
      setBusy(false);
    }
  };

  const addStage = () =>
    handle(async () => {
      if (!newName.trim()) throw new Error("Name required");
      await productionStagesApi.add(orderId, {
        name: newName.trim(),
        supplier_id: newSupplierId || null,
        unit_cost: newUnitCost ? Number(newUnitCost) : null,
        cost_currency: po?.cost_currency || "EGP",
        notes: newNotes.trim() || null,
      });
      setNewName("cutting");
      setNewSupplierId("");
      setNewUnitCost("");
      setNewNotes("");
    });

  const startStage = (s: ProductionStage) =>
    handle(() => productionStagesApi.start(orderId, s.id));

  const completeStage = (s: ProductionStage) =>
    handle(() => productionStagesApi.complete(orderId, s.id));

  const skipStage = (s: ProductionStage) =>
    handle(() =>
      productionStagesApi.update(orderId, s.id, { status: "skipped" }),
    );

  const removeStage = (s: ProductionStage) => {
    if (!window.confirm(`Remove stage "${s.name}"?`)) return;
    handle(() => productionStagesApi.destroy(orderId, s.id));
  };

  return (
    <div
      className="fixed inset-0 bg-black/40 flex justify-end z-50"
      onClick={onClose}
    >
      <div
        className="bg-white w-full max-w-2xl h-full overflow-auto shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 bg-white border-b border-slate-200 px-6 py-4 flex items-start justify-between">
          <div>
            <h2 className="text-lg font-semibold">
              Production stages{po ? ` — ${po.number}` : ""}
            </h2>
            {po?.parent_variant && (
              <div className="text-xs text-slate-500 mt-1">
                {po.parent_variant.product_title} · {po.parent_variant.sku} ·
                qty {po.quantity}
              </div>
            )}
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-700"
          >
            ✕
          </button>
        </div>

        <div className="p-6 space-y-6">
          {error && (
            <div className="rounded-md bg-rose-50 text-rose-700 px-3 py-2 text-sm">
              {error}
            </div>
          )}

          {loading ? (
            <div className="text-sm text-slate-500">Loading…</div>
          ) : (
            <>
              <section>
                <h3 className="text-sm font-medium text-slate-700 mb-2">
                  Timeline
                </h3>
                {(po?.stages?.length ?? 0) === 0 ? (
                  <div className="text-sm text-slate-500 border border-dashed border-slate-300 rounded-lg p-4">
                    No stages yet. Add the first stage below.
                  </div>
                ) : (
                  <ol className="space-y-2">
                    {po!.stages!.map((s) => (
                      <li
                        key={s.id}
                        className="border border-slate-200 rounded-lg p-3 flex items-start justify-between gap-3"
                      >
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="text-xs text-slate-400 tabular-nums">
                              #{s.position + 1}
                            </span>
                            <span className="font-medium text-slate-900 capitalize">
                              {s.name}
                            </span>
                            <span
                              className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
                                STATUS_STYLES[s.status] || STATUS_STYLES.pending
                              }`}
                            >
                              {s.status.replace("_", " ")}
                            </span>
                          </div>
                          <div className="text-xs text-slate-500 mt-1 space-x-3">
                            {s.supplier_name && (
                              <span>📦 {s.supplier_name}</span>
                            )}
                            {s.unit_cost && (
                              <span>
                                💰 {s.unit_cost} {s.cost_currency}/unit
                              </span>
                            )}
                            {s.started_at && (
                              <span>
                                ▶ {new Date(s.started_at).toLocaleString()}
                              </span>
                            )}
                            {s.completed_at && (
                              <span>
                                ✓ {new Date(s.completed_at).toLocaleString()}
                              </span>
                            )}
                          </div>
                          {s.notes && (
                            <div className="text-xs text-slate-600 mt-1">
                              {s.notes}
                            </div>
                          )}
                        </div>
                        <div className="flex flex-col gap-1 items-end">
                          {s.status === "pending" && (
                            <button
                              disabled={busy}
                              onClick={() => startStage(s)}
                              className="text-xs bg-sky-600 text-white px-2 py-1 rounded hover:bg-sky-700 disabled:opacity-60"
                            >
                              Start
                            </button>
                          )}
                          {s.status === "in_progress" && (
                            <button
                              disabled={busy}
                              onClick={() => completeStage(s)}
                              className="text-xs bg-emerald-600 text-white px-2 py-1 rounded hover:bg-emerald-700 disabled:opacity-60"
                            >
                              Complete
                            </button>
                          )}
                          {(s.status === "pending" ||
                            s.status === "in_progress") && (
                            <button
                              disabled={busy}
                              onClick={() => skipStage(s)}
                              className="text-xs bg-amber-50 text-amber-700 ring-1 ring-inset ring-amber-600/20 px-2 py-1 rounded hover:bg-amber-100 disabled:opacity-60"
                            >
                              Skip
                            </button>
                          )}
                          {s.status === "pending" && (
                            <button
                              disabled={busy}
                              onClick={() => removeStage(s)}
                              className="text-xs text-rose-600 hover:underline disabled:opacity-60"
                            >
                              Remove
                            </button>
                          )}
                        </div>
                      </li>
                    ))}
                  </ol>
                )}
              </section>

              <section className="border-t border-slate-200 pt-4">
                <h3 className="text-sm font-medium text-slate-700 mb-2">
                  Add stage
                </h3>
                <div className="grid grid-cols-2 gap-3">
                  <div className="col-span-1">
                    <label className="text-xs text-slate-600">Name</label>
                    <input
                      list="stage-presets"
                      value={newName}
                      onChange={(e) => setNewName(e.target.value)}
                      className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                    />
                    <datalist id="stage-presets">
                      {STAGE_PRESETS.map((p) => (
                        <option key={p} value={p} />
                      ))}
                    </datalist>
                  </div>
                  <div className="col-span-1">
                    <label className="text-xs text-slate-600">
                      Factory / supplier
                    </label>
                    <select
                      value={newSupplierId}
                      onChange={(e) => setNewSupplierId(e.target.value)}
                      className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                    >
                      <option value="">— in-house —</option>
                      {suppliers.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="col-span-1">
                    <label className="text-xs text-slate-600">
                      Unit cost ({po?.cost_currency || "EGP"})
                    </label>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={newUnitCost}
                      onChange={(e) => setNewUnitCost(e.target.value)}
                      className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                    />
                  </div>
                  <div className="col-span-1">
                    <label className="text-xs text-slate-600">Notes</label>
                    <input
                      type="text"
                      value={newNotes}
                      onChange={(e) => setNewNotes(e.target.value)}
                      className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                    />
                  </div>
                </div>
                <div className="mt-3 flex justify-end">
                  <button
                    disabled={busy}
                    onClick={addStage}
                    className="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-60"
                  >
                    Add stage
                  </button>
                </div>
              </section>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
