import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  fulfillmentsApi,
  type Fulfillment,
  type ShipmentEvent,
} from "../api/fulfillments";
import DeliveryActions from "../components/shipments/DeliveryActions";

function formatDate(value?: string | null) {
  return value ? new Date(value).toLocaleString() : "-";
}

export default function ShipmentDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [shipment, setShipment] = useState<Fulfillment | null>(null);
  const [events, setEvents] = useState<ShipmentEvent[]>([]);
  const [notes, setNotes] = useState("");
  const [tagInput, setTagInput] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    Promise.all([fulfillmentsApi.get(id), fulfillmentsApi.events(id)])
      .then(([row, eventRows]) => {
        setShipment(row);
        setNotes(row.notes || "");
        setEvents(eventRows);
      })
      .catch((e) =>
        setError((e as Error).message || "Failed to load shipment"),
      );
  }, [id]);

  async function saveAnnotation() {
    if (!shipment) return;
    setSaving(true);
    try {
      const updated = await fulfillmentsApi.annotate(shipment.id, {
        notes,
        tags: shipment.tags || [],
      });
      setShipment(updated);
      const eventRows = await fulfillmentsApi.events(shipment.id);
      setEvents(eventRows);
    } finally {
      setSaving(false);
    }
  }

  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!shipment)
    return (
      <div className="p-6 text-sm text-slate-500">Loading shipment...</div>
    );

  const address = (shipment.order?.shipping_address || {}) as Record<
    string,
    unknown
  >;

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div>
        <Link
          to="/shipments"
          className="text-sm text-slate-500 hover:text-slate-700"
        >
          Back to Shipments
        </Link>
        <h1 className="text-2xl font-semibold text-slate-900 mt-1">
          {shipment.tracking_number || `Shipment ${shipment.id.slice(0, 8)}`}
        </h1>
        <div className="mt-2 flex flex-wrap gap-2 text-xs text-slate-600">
          <span className="rounded bg-slate-100 px-2 py-1 capitalize">
            {shipment.status}
          </span>
          {shipment.delivery_status && (
            <span className="rounded bg-slate-100 px-2 py-1 capitalize">
              {shipment.delivery_status}
            </span>
          )}
          <span className="rounded bg-slate-100 px-2 py-1 capitalize">
            {shipment.carrier || shipment.tracking_company || "carrier unknown"}
          </span>
        </div>
        <div className="mt-3">
          <DeliveryActions
            fulfillment={shipment}
            onUpdated={(updated) => {
              setShipment(updated);
              fulfillmentsApi
                .events(updated.id)
                .then(setEvents)
                .catch(() => {});
            }}
          />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <section className="bg-white rounded-xl border border-slate-200 p-4 lg:col-span-2">
          <h2 className="text-sm font-semibold text-slate-900 mb-3">
            Tracking
          </h2>
          <dl className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
            <Info
              label="Tracking number"
              value={shipment.tracking_number || "-"}
              mono
            />
            <Info label="Carrier" value={shipment.tracking_company || "-"} />
            <Info label="Shipped" value={formatDate(shipment.shipped_at)} />
            <Info label="Delivered" value={formatDate(shipment.delivered_at)} />
            <Info label="Service" value={shipment.service || "-"} />
            <Info
              label="Shopify fulfillment"
              value={
                shipment.shopify_fulfillment_id
                  ? String(shipment.shopify_fulfillment_id)
                  : "Manual"
              }
              mono
            />
          </dl>
          {shipment.tracking_url && (
            <a
              className="mt-4 inline-flex text-sm font-medium text-indigo-700 hover:underline"
              href={shipment.tracking_url}
              target="_blank"
              rel="noreferrer"
            >
              Open carrier tracking
            </a>
          )}
        </section>

        <section className="bg-white rounded-xl border border-slate-200 p-4">
          <h2 className="text-sm font-semibold text-slate-900 mb-3">
            Order & customer
          </h2>
          {shipment.order && (
            <Link
              to={`/orders/${shipment.order.id}`}
              className="font-mono text-sm text-indigo-700 hover:underline"
            >
              {shipment.order.order_number}
            </Link>
          )}
          <div className="mt-3 text-sm text-slate-700">
            {shipment.customer?.name || shipment.customer?.email || "-"}
          </div>
          <div className="text-xs text-slate-500">
            {shipment.customer?.email || ""}
          </div>
          <div className="mt-3 text-xs text-slate-500 leading-5">
            {[
              address.address1,
              address.address2,
              address.city,
              address.province,
              address.country,
              address.zip,
            ]
              .filter(Boolean)
              .map(String)
              .join(", ") || "No shipping address"}
          </div>
        </section>
      </div>

      <section className="bg-white rounded-xl border border-slate-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-200 text-sm font-semibold text-slate-900">
          Items
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-[640px] text-sm">
            <thead className="bg-slate-50 text-xs uppercase text-slate-500">
              <tr>
                <th className="px-4 py-2 text-left">Item</th>
                <th className="px-4 py-2 text-left">SKU</th>
                <th className="px-4 py-2 text-right">Qty</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(shipment.line_items || []).map((item) => (
                <tr key={item.id}>
                  <td className="px-4 py-2">
                    {item.title || item.variant_title || "Item"}
                  </td>
                  <td className="px-4 py-2 font-mono text-xs text-slate-500">
                    {item.sku || "-"}
                  </td>
                  <td className="px-4 py-2 text-right">{item.quantity}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <section className="bg-white rounded-xl border border-slate-200 p-4">
          <h2 className="text-sm font-semibold text-slate-900 mb-3">
            Timeline
          </h2>
          <div className="space-y-3">
            {events.map((event) => (
              <div key={event.id} className="border-l-2 border-indigo-200 pl-3">
                <div className="text-sm font-medium text-slate-800 capitalize">
                  {event.kind.replace(/_/g, " ")}
                </div>
                <div className="text-xs text-slate-500">
                  {formatDate(event.created_at)}
                </div>
              </div>
            ))}
            {events.length === 0 && (
              <div className="text-sm text-slate-400">
                No timeline events yet.
              </div>
            )}
          </div>
        </section>

        <section className="bg-white rounded-xl border border-slate-200 p-4 space-y-3">
          <h2 className="text-sm font-semibold text-slate-900">Notes & tags</h2>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={5}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
          />
          <div className="flex flex-wrap gap-1">
            {(shipment.tags || []).map((tag) => (
              <button
                key={tag}
                onClick={() =>
                  setShipment({
                    ...shipment,
                    tags: (shipment.tags || []).filter((t) => t !== tag),
                  })
                }
                className="rounded bg-slate-100 px-2 py-1 text-xs text-slate-700"
              >
                {tag} x
              </button>
            ))}
          </div>
          <input
            value={tagInput}
            onChange={(e) => setTagInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && tagInput.trim()) {
                setShipment({
                  ...shipment,
                  tags: [...(shipment.tags || []), tagInput.trim()],
                });
                setTagInput("");
              }
            }}
            placeholder="Add tag and press Enter"
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
          />
          <button
            disabled={saving}
            onClick={saveAnnotation}
            className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          >
            {saving ? "Saving..." : "Save notes"}
          </button>
        </section>
      </div>
    </div>
  );
}

function Info({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div>
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd className={`text-slate-900 ${mono ? "font-mono text-xs" : ""}`}>
        {value}
      </dd>
    </div>
  );
}
