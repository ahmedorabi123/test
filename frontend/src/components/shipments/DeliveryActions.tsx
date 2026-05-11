import { useState } from "react";
import { fulfillmentsApi, type Fulfillment } from "../../api/fulfillments";

const LEGAL: Record<string, Array<"in_transit" | "delivered" | "failed">> = {
  pending: ["in_transit", "delivered", "failed"],
  in_transit: ["delivered", "failed"],
  delivered: [],
  failed: [],
};

const LABEL: Record<string, string> = {
  in_transit: "Mark In Transit",
  delivered: "Mark Delivered",
  failed: "Mark Failed",
};

const STYLE: Record<string, string> = {
  in_transit: "bg-blue-600 hover:bg-blue-700",
  delivered: "bg-emerald-600 hover:bg-emerald-700",
  failed: "bg-rose-600 hover:bg-rose-700",
};

interface Props {
  fulfillment: Fulfillment;
  onUpdated: (updated: Fulfillment) => void;
  size?: "sm" | "md";
  className?: string;
}

export default function DeliveryActions({
  fulfillment,
  onUpdated,
  size = "md",
  className = "",
}: Props) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const current = (fulfillment.delivery_status || "pending").toLowerCase();
  const next = LEGAL[current] ?? [];

  if (next.length === 0) {
    return (
      <span className="text-xs text-slate-500 capitalize">
        {current.replace(/_/g, " ")}
      </span>
    );
  }

  async function go(to: "in_transit" | "delivered" | "failed") {
    setBusy(to);
    setError(null);
    try {
      const updated = await fulfillmentsApi.transitionDelivery(
        fulfillment.id,
        to,
      );
      onUpdated(updated);
    } catch (e) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
      };
      setError(
        err.response?.data?.error?.detail ?? "Failed to update delivery",
      );
    } finally {
      setBusy(null);
    }
  }

  const padding = size === "sm" ? "px-2 py-1 text-xs" : "px-3 py-1.5 text-sm";

  return (
    <div className={`flex flex-wrap items-center gap-2 ${className}`}>
      {next.map((to) => (
        <button
          key={to}
          onClick={() => go(to)}
          disabled={busy !== null}
          className={`rounded-md font-medium text-white disabled:opacity-50 transition ${padding} ${STYLE[to]}`}
        >
          {busy === to ? "…" : LABEL[to]}
        </button>
      ))}
      {error && <span className="text-xs text-rose-600">{error}</span>}
    </div>
  );
}
