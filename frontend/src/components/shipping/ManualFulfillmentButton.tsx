import { useState } from "react";
import type { Order } from "../../api/orders";
import { fulfillmentsApi } from "../../api/fulfillments";

interface LineRow {
  order_line_item_id: string;
  quantity: number;
  enabled: boolean;
  label: string;
  max: number;
}

export default function ManualFulfillmentButton({
  order,
  onCreated,
}: {
  order: Order;
  onCreated: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [carrier, setCarrier] = useState("Bosta");
  const [trackingNumber, setTrackingNumber] = useState("");
  const [trackingUrl, setTrackingUrl] = useState("");
  const [transitionOrder, setTransitionOrder] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [rows, setRows] = useState<LineRow[]>([]);

  const initRows = () => {
    setRows(
      (order.line_items ?? []).map((li) => ({
        order_line_item_id: li.id,
        quantity: li.quantity,
        enabled: true,
        label: `${li.title}${li.variant_title ? ` · ${li.variant_title}` : ""} (${li.sku ?? "—"})`,
        max: li.quantity,
      })),
    );
  };

  const openModal = () => {
    setErr(null);
    setCarrier("Bosta");
    setTrackingNumber("");
    setTrackingUrl("");
    setTransitionOrder(order.status !== "fulfilled");
    initRows();
    setOpen(true);
  };

  const submit = async () => {
    if (!carrier.trim()) {
      setErr("Carrier / tracking company is required");
      return;
    }
    setSubmitting(true);
    setErr(null);
    try {
      await fulfillmentsApi.create({
        order_id: order.id,
        tracking_company: carrier.trim(),
        tracking_number: trackingNumber.trim() || undefined,
        tracking_url: trackingUrl.trim() || undefined,
        transition_order: transitionOrder,
        line_items: rows
          .filter((r) => r.enabled && r.quantity > 0)
          .map((r) => ({
            order_line_item_id: r.order_line_item_id,
            quantity: r.quantity,
          })),
      });
      setOpen(false);
      onCreated();
    } catch (e) {
      const x = e as {
        response?: { data?: { error?: { detail?: string; message?: string } } };
        message?: string;
      };
      setErr(
        x.response?.data?.error?.detail ||
          x.response?.data?.error?.message ||
          x.message ||
          "Failed to create fulfillment",
      );
    } finally {
      setSubmitting(false);
    }
  };

  if (order.status === "cancelled") return null;

  return (
    <>
      <button
        onClick={openModal}
        className="px-3 py-2 text-sm bg-sky-600 text-white rounded-lg hover:bg-sky-700"
      >
        Create shipment
      </button>

      {open && (
        <div
          className="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
          onClick={() => setOpen(false)}
        >
          <div
            className="bg-white rounded-xl shadow-xl w-full max-w-xl p-6 space-y-4 max-h-[90vh] overflow-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between">
              <h2 className="text-lg font-semibold">
                Create shipment for {order.order_number}
              </h2>
              <button
                onClick={() => setOpen(false)}
                className="text-slate-400 hover:text-slate-700"
              >
                ✕
              </button>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-slate-600">Carrier</label>
                <input
                  list="carrier-presets"
                  value={carrier}
                  onChange={(e) => setCarrier(e.target.value)}
                  className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                />
                <datalist id="carrier-presets">
                  <option value="Bosta" />
                  <option value="Aramex" />
                  <option value="DHL" />
                  <option value="Manual" />
                  <option value="Pickup" />
                </datalist>
              </div>
              <div>
                <label className="text-xs text-slate-600">
                  Tracking number
                </label>
                <input
                  value={trackingNumber}
                  onChange={(e) => setTrackingNumber(e.target.value)}
                  className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                />
              </div>
              <div className="col-span-2">
                <label className="text-xs text-slate-600">Tracking URL</label>
                <input
                  value={trackingUrl}
                  onChange={(e) => setTrackingUrl(e.target.value)}
                  placeholder="https://…"
                  className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
                />
              </div>
            </div>

            <div>
              <div className="text-xs text-slate-600 mb-1">Line items</div>
              <div className="border border-slate-200 rounded-lg divide-y divide-slate-100">
                {rows.length === 0 && (
                  <div className="px-3 py-4 text-sm text-slate-500">
                    No line items on this order.
                  </div>
                )}
                {rows.map((r, i) => (
                  <div
                    key={r.order_line_item_id}
                    className="px-3 py-2 flex items-center gap-2"
                  >
                    <input
                      type="checkbox"
                      checked={r.enabled}
                      onChange={(e) => {
                        const next = [...rows];
                        next[i] = { ...r, enabled: e.target.checked };
                        setRows(next);
                      }}
                    />
                    <div className="flex-1 text-sm">{r.label}</div>
                    <input
                      type="number"
                      min={1}
                      max={r.max}
                      value={r.quantity}
                      disabled={!r.enabled}
                      onChange={(e) => {
                        const next = [...rows];
                        next[i] = {
                          ...r,
                          quantity: Math.max(
                            1,
                            Math.min(
                              r.max,
                              parseInt(e.target.value || "1", 10),
                            ),
                          ),
                        };
                        setRows(next);
                      }}
                      className="w-20 border border-slate-300 rounded px-2 py-1 text-sm tabular-nums"
                    />
                    <span className="text-xs text-slate-400">/ {r.max}</span>
                  </div>
                ))}
              </div>
            </div>

            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={transitionOrder}
                onChange={(e) => setTransitionOrder(e.target.checked)}
              />
              Mark order as fulfilled (deducts stock + posts COGS)
            </label>

            {err && <div className="text-sm text-rose-600">{err}</div>}

            <div className="flex justify-end gap-2 pt-2">
              <button
                onClick={() => setOpen(false)}
                className="px-3 py-2 text-sm rounded-lg border border-slate-300 hover:bg-slate-50"
              >
                Cancel
              </button>
              <button
                onClick={submit}
                disabled={submitting}
                className="px-3 py-2 text-sm bg-sky-600 text-white rounded-lg hover:bg-sky-700 disabled:opacity-60"
              >
                {submitting ? "Creating…" : "Create shipment"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
