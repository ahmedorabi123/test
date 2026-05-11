import { useEffect, useState } from "react";
import { refundsApi } from "../../api/refunds";
import { warehousesApi, type Warehouse } from "../../api/inventory";
import api from "../../api/client";
import { Modal } from "../ui/Modal";

interface OrderOption {
  id: string;
  order_number: string;
  total_price: string;
  currency: string;
  customer_name?: string;
}

interface OrderLineItem {
  id: string;
  title: string;
  variant_title?: string;
  sku?: string;
  quantity: number;
  price: string;
}

interface OrderDetail extends OrderOption {
  line_items: OrderLineItem[];
  status?: string;
  financial_status?: string;
}

const REFUNDABLE_FINANCIAL_STATES = [
  "paid",
  "partially_paid",
  "partially_refunded",
];

function orderIneligibleReason(o: OrderDetail | null): string | null {
  if (!o) return null;
  if (o.status === "cancelled") return "Cancelled orders cannot be refunded.";
  if (
    o.financial_status &&
    !REFUNDABLE_FINANCIAL_STATES.includes(o.financial_status)
  ) {
    return `Order is ${o.financial_status.replace(/_/g, " ")} — only paid, partially paid, or partially refunded orders can be refunded.`;
  }
  return null;
}

interface RefundLineDraft {
  order_line_item_id: string;
  quantity: string;
  subtotal: string;
}

export default function ManualRefundButton({
  onCreated,
}: {
  onCreated: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [orderQuery, setOrderQuery] = useState("");
  const [orderResults, setOrderResults] = useState<OrderOption[]>([]);
  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [restock, setRestock] = useState(false);
  const [restockWarehouseId, setRestockWarehouseId] = useState("");
  const [lines, setLines] = useState<RefundLineDraft[]>([]);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (open) {
      warehousesApi
        .list()
        .then(setWarehouses)
        .catch(() => undefined);
    }
  }, [open]);

  useEffect(() => {
    if (orderQuery.trim().length < 2) {
      setOrderResults([]);
      return;
    }
    const t = setTimeout(() => {
      api
        .get<{ data: OrderOption[] }>("/orders", {
          params: { search: orderQuery, per_page: 10 },
        })
        .then((r) => setOrderResults(r.data.data))
        .catch(() => undefined);
    }, 300);
    return () => clearTimeout(t);
  }, [orderQuery]);

  const pickOrder = async (id: string) => {
    const r = await api.get<{ data: OrderDetail }>(`/orders/${id}`);
    setOrder(r.data.data);
    setLines(
      r.data.data.line_items.map((li) => ({
        order_line_item_id: li.id,
        quantity: "0",
        subtotal: "0.00",
      })),
    );
    setAmount("");
    setOrderResults([]);
    setOrderQuery(r.data.data.order_number);
  };

  const recomputeAmount = (next: RefundLineDraft[]) => {
    const sum = next.reduce((acc, l) => acc + Number(l.subtotal || 0), 0);
    setAmount(sum.toFixed(2));
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!order) return;
    setError("");
    const ineligible = orderIneligibleReason(order);
    if (ineligible) {
      setError(ineligible);
      return;
    }
    if (Number(amount) <= 0) {
      setError("Amount must be > 0");
      return;
    }
    if (restock && !restockWarehouseId) {
      setError("Pick a warehouse to restock to");
      return;
    }
    const selectedLines = lines.filter((l) => Number(l.quantity) > 0);
    if (restock && selectedLines.length === 0) {
      setError("Select at least one line item to restock");
      return;
    }
    setSubmitting(true);
    try {
      await refundsApi.create({
        order_id: order.id,
        amount,
        currency: order.currency,
        reason: reason || undefined,
        note: note || undefined,
        restock,
        restock_warehouse_id: restock ? restockWarehouseId : undefined,
        line_items: selectedLines.map((l) => ({
          order_line_item_id: l.order_line_item_id,
          quantity: Number(l.quantity),
          subtotal: l.subtotal,
        })),
      });
      reset();
      setOpen(false);
      onCreated();
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data
          ?.error || (e as Error).message;
      setError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  const reset = () => {
    setOrder(null);
    setOrderQuery("");
    setOrderResults([]);
    setAmount("");
    setReason("");
    setNote("");
    setRestock(false);
    setRestockWarehouseId("");
    setLines([]);
    setError("");
  };

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1 bg-indigo-600 text-white text-sm font-medium px-3 py-2 rounded-lg hover:bg-indigo-700"
      >
        + Manual refund
      </button>
      <Modal
        open={open}
        onClose={() => {
          reset();
          setOpen(false);
        }}
        size="xl"
        title="New manual refund"
      >
            <form onSubmit={submit} className="space-y-3">
              <div className="relative">
                <label className="block text-sm">
                  <span className="block text-slate-600 mb-1">Order *</span>
                  <input
                    value={orderQuery}
                    onChange={(e) => {
                      setOrderQuery(e.target.value);
                      setOrder(null);
                    }}
                    placeholder="Search by order # or email"
                    className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                  />
                </label>
                {orderResults.length > 0 && !order && (
                  <ul className="absolute z-10 left-0 right-0 bg-white border border-slate-200 rounded shadow mt-1 max-h-48 overflow-y-auto text-sm">
                    {orderResults.map((o) => (
                      <li
                        key={o.id}
                        onClick={() => pickOrder(o.id)}
                        className="flex cursor-pointer flex-col gap-1 px-3 py-2 hover:bg-indigo-50 sm:flex-row sm:justify-between"
                      >
                        <span>
                          <strong>{o.order_number}</strong> —{" "}
                          {o.customer_name || "—"}
                        </span>
                        <span className="text-slate-500">
                          {o.currency} {o.total_price}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {order && (
                <>
                  {orderIneligibleReason(order) && (
                    <div className="rounded-md bg-amber-50 border border-amber-200 text-amber-800 text-sm px-3 py-2">
                      {orderIneligibleReason(order)}
                    </div>
                  )}
                  <div className="rounded border border-slate-200">
                    <div className="overflow-x-auto">
                    <table className="min-w-[680px] text-sm">
                      <thead className="bg-slate-50 text-xs text-slate-600 uppercase">
                        <tr>
                          <th className="px-2 py-2 text-left">Line item</th>
                          <th className="px-2 py-2 text-right w-20">
                            Qty avail
                          </th>
                          <th className="px-2 py-2 text-right w-20">
                            Refund qty
                          </th>
                          <th className="px-2 py-2 text-right w-28">
                            Subtotal
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {order.line_items.map((li, idx) => (
                          <tr key={li.id} className="border-t border-slate-100">
                            <td className="px-2 py-1">
                              <div className="font-medium text-slate-800">
                                {li.title}
                              </div>
                              <div className="text-xs text-slate-500">
                                {li.variant_title} · {li.sku}
                              </div>
                            </td>
                            <td className="px-2 py-1 text-right">
                              {li.quantity}
                            </td>
                            <td className="px-2 py-1 text-right">
                              <input
                                type="number"
                                min={0}
                                max={li.quantity}
                                value={lines[idx]?.quantity ?? "0"}
                                onChange={(e) => {
                                  const q = Number(e.target.value || 0);
                                  const subtotal = (
                                    q * Number(li.price)
                                  ).toFixed(2);
                                  setLines((arr) => {
                                    const next = arr.map((x, i) =>
                                      i === idx
                                        ? {
                                            ...x,
                                            quantity: e.target.value,
                                            subtotal,
                                          }
                                        : x,
                                    );
                                    recomputeAmount(next);
                                    return next;
                                  });
                                }}
                                className="w-16 border border-slate-200 rounded px-2 py-1 text-right"
                              />
                            </td>
                            <td className="px-2 py-1 text-right">
                              <input
                                type="number"
                                step="0.01"
                                min={0}
                                value={lines[idx]?.subtotal ?? "0"}
                                onChange={(e) => {
                                  setLines((arr) => {
                                    const next = arr.map((x, i) =>
                                      i === idx
                                        ? { ...x, subtotal: e.target.value }
                                        : x,
                                    );
                                    recomputeAmount(next);
                                    return next;
                                  });
                                }}
                                className="w-24 border border-slate-200 rounded px-2 py-1 text-right"
                              />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    </div>
                  </div>

                  <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
                    <label className="text-sm">
                      <span className="block text-slate-600 mb-1">
                        Total amount *
                      </span>
                      <input
                        type="number"
                        step="0.01"
                        min={0}
                        required
                        value={amount}
                        onChange={(e) => setAmount(e.target.value)}
                        className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                      />
                    </label>
                    <label className="text-sm">
                      <span className="block text-slate-600 mb-1">Reason</span>
                      <select
                        value={reason}
                        onChange={(e) => setReason(e.target.value)}
                        className="min-h-11 w-full rounded border border-slate-300 px-3 py-2"
                      >
                        <option value="">—</option>
                        <option value="customer_change">
                          Customer change of mind
                        </option>
                        <option value="defective">Defective / damaged</option>
                        <option value="wrong_item">Wrong item shipped</option>
                        <option value="estebdal">
                          Estebdal (Egypt exchange)
                        </option>
                        <option value="showroom_return">Showroom return</option>
                        <option value="other">Other</option>
                      </select>
                    </label>
                    <label className="text-sm">
                      <span className="text-slate-600 mb-1 flex items-center gap-2">
                        <input
                          type="checkbox"
                          checked={restock}
                          onChange={(e) => setRestock(e.target.checked)}
                        />
                        Restock to warehouse
                      </span>
                      <select
                        value={restockWarehouseId}
                        onChange={(e) => setRestockWarehouseId(e.target.value)}
                        disabled={!restock}
                        className="min-h-11 w-full rounded border border-slate-300 px-3 py-2 disabled:bg-slate-100"
                      >
                        <option value="">—</option>
                        {warehouses.map((w) => (
                          <option key={w.id} value={w.id}>
                            {w.name} ({w.code})
                          </option>
                        ))}
                      </select>
                    </label>
                  </div>

                  <label className="block text-sm">
                    <span className="block text-slate-600 mb-1">Note</span>
                    <textarea
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      rows={2}
                      className="w-full rounded border border-slate-300 px-3 py-2"
                    />
                  </label>
                </>
              )}

              {error && (
                <div className="bg-red-50 text-red-700 text-sm p-2 rounded">
                  {error}
                </div>
              )}

              <div className="flex flex-col-reverse gap-2 pt-1 sm:flex-row sm:justify-end">
                <button
                  type="button"
                  onClick={() => {
                    reset();
                    setOpen(false);
                  }}
                  className="min-h-11 rounded border border-slate-300 px-3 text-sm"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={
                    submitting ||
                    !order ||
                    orderIneligibleReason(order) !== null
                  }
                  className="min-h-11 rounded bg-indigo-600 px-4 text-sm font-medium text-white hover:bg-indigo-700 disabled:bg-slate-400"
                >
                  {submitting ? "Posting…" : "Post refund"}
                </button>
              </div>
            </form>
      </Modal>
    </>
  );
}
