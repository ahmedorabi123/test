import { useState } from "react";
import type { Order } from "../../api/orders";
import { fulfillmentsApi } from "../../api/fulfillments";
import { Modal } from "../ui/Modal";

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

  if (order.status === "cancelled" || order.read_only_origin) return null;

  return (
    <>
      <button
        onClick={openModal}
        className="px-3 py-2 text-sm bg-sky-600 text-white rounded-lg hover:bg-sky-700"
      >
        Create shipment
      </button>

      <Modal
        open={open}
        onClose={() => setOpen(false)}
        size="lg"
        title={`Create shipment for ${order.order_number}`}
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label className="text-xs text-slate-600">Carrier</label>
              <input
                list="carrier-presets"
                value={carrier}
                onChange={(e) => setCarrier(e.target.value)}
                className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
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
              <label className="text-xs text-slate-600">Tracking number</label>
              <input
                value={trackingNumber}
                onChange={(e) => setTrackingNumber(e.target.value)}
                className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </div>
            <div className="sm:col-span-2">
              <label className="text-xs text-slate-600">Tracking URL</label>
              <input
                value={trackingUrl}
                onChange={(e) => setTrackingUrl(e.target.value)}
                placeholder="https://…"
                className="min-h-11 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
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
                  className="flex flex-col gap-2 px-3 py-2 sm:flex-row sm:items-center"
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
                          Math.min(r.max, parseInt(e.target.value || "1", 10)),
                        ),
                      };
                      setRows(next);
                    }}
                    className="min-h-10 w-full rounded border border-slate-300 px-2 py-1 text-sm tabular-nums sm:w-20"
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

          <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
            <button
              onClick={() => setOpen(false)}
              className="min-h-11 rounded-lg border border-slate-300 px-3 text-sm hover:bg-slate-50"
            >
              Cancel
            </button>
            <button
              onClick={submit}
              disabled={submitting}
              className="min-h-11 rounded-lg bg-sky-600 px-3 text-sm text-white hover:bg-sky-700 disabled:opacity-60"
            >
              {submitting ? "Creating…" : "Create shipment"}
            </button>
          </div>
        </div>
      </Modal>
    </>
  );
}
