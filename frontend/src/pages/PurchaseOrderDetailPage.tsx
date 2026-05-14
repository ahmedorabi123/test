import { useCallback, useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { purchaseOrdersApi, type PurchaseOrder } from "../api/purchaseOrders";

export default function PurchaseOrderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [po, setPo] = useState<PurchaseOrder | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!id) return;
    try {
      const data = await purchaseOrdersApi.get(id);
      setPo(data);
      const q: Record<string, number> = {};
      (data.line_items || []).forEach((li) => {
        q[li.id] = li.remaining;
      });
      setQuantities(q);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);

  const markOrdered = async () => {
    if (!po) return;
    await purchaseOrdersApi.update(po.id, { status: "ordered" });
    load();
  };

  const receive = async () => {
    if (!po) return;
    setBusy(true);
    setError(null);
    try {
      const receipts = Object.entries(quantities)
        .filter(([, q]) => q > 0)
        .map(([line_item_id, q]) => ({ line_item_id, quantity: q }));
      if (receipts.length === 0) {
        setError("Enter at least one quantity to receive");
        return;
      }
      await purchaseOrdersApi.receive(po.id, receipts);
      await load();
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        err.response?.data?.error?.detail || err.message || "Receive failed",
      );
    } finally {
      setBusy(false);
    }
  };

  const cancel = async () => {
    if (!po) return;
    if (!confirm("Cancel this PO?")) return;
    await purchaseOrdersApi.cancel(po.id);
    load();
  };

  if (!po) return <div className="p-6">Loading…</div>;

  const canReceive = ["ordered", "partial"].includes(po.status);

  return (
    <div className="p-6 max-w-4xl">
      <Link to="/purchases" className="text-indigo-600 text-sm hover:underline">
        ← Back
      </Link>

      <div className="flex items-center justify-between mt-2 mb-4">
        <div>
          <h1 className="text-2xl font-semibold">{po.po_number}</h1>
          <div className="text-sm text-gray-500">
            {po.supplier_name} • {po.warehouse_name || "no warehouse"} • status:{" "}
            <strong>{po.status}</strong>
          </div>
        </div>
        <div className="flex gap-2">
          {po.status === "draft" && (
            <button
              onClick={markOrdered}
              className="px-3 py-1 bg-blue-600 text-white rounded text-sm"
            >
              Mark as ordered
            </button>
          )}
          {po.status !== "cancelled" && po.status !== "received" && (
            <button
              onClick={cancel}
              className="px-3 py-1 border rounded text-sm"
            >
              Cancel
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="bg-red-100 text-red-700 p-2 mb-3 rounded">{error}</div>
      )}

      <div className="bg-white rounded shadow overflow-x-auto mb-4">
        <table className="min-w-[640px] text-sm">
          <thead className="bg-gray-50 text-left">
            <tr>
              <th className="px-3 py-2">Item</th>
              <th className="px-3 py-2 text-right">Ordered</th>
              <th className="px-3 py-2 text-right">Received</th>
              <th className="px-3 py-2 text-right">Remaining</th>
              {canReceive && (
                <th className="px-3 py-2 text-right">Receive now</th>
              )}
            </tr>
          </thead>
          <tbody>
            {(po.line_items || []).map((li) => (
              <tr key={li.id} className="border-t">
                <td className="px-3 py-2">{li.title || li.sku}</td>
                <td className="px-3 py-2 text-right">{li.quantity_ordered}</td>
                <td className="px-3 py-2 text-right">{li.quantity_received}</td>
                <td className="px-3 py-2 text-right">{li.remaining}</td>
                {canReceive && (
                  <td className="px-3 py-2 text-right">
                    <input
                      type="number"
                      min={0}
                      max={li.remaining}
                      value={quantities[li.id] ?? 0}
                      onChange={(e) =>
                        setQuantities((q) => ({
                          ...q,
                          [li.id]: Math.max(
                            0,
                            Math.min(li.remaining, Number(e.target.value)),
                          ),
                        }))
                      }
                      className="w-20 border rounded px-2 py-0.5 text-right"
                    />
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {canReceive && (
        <button
          onClick={receive}
          disabled={busy}
          className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded text-sm disabled:opacity-50"
        >
          {busy ? "Receiving…" : "Receive selected quantities"}
        </button>
      )}
    </div>
  );
}
