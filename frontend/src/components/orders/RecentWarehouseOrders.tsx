import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ordersApi, type Order } from "../../api/orders";

interface Props {
  warehouseId: string;
  warehouseName?: string;
  className?: string;
}

export function RecentWarehouseOrders({
  warehouseId,
  warehouseName,
  className = "",
}: Props) {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!warehouseId) {
      setOrders([]);
      return;
    }

    let active = true;
    setLoading(true);
    setError(null);
    ordersApi
      .list({
        warehouse_id: warehouseId,
        per_page: 5,
        sort: "placed_at",
        dir: "desc",
      })
      .then((res) => {
        if (active) setOrders(res.data);
      })
      .catch((err: Error) => {
        if (active) setError(err.message || "Failed to load recent orders");
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [warehouseId]);

  return (
    <section
      className={`rounded-xl border border-slate-200 bg-white p-4 shadow-sm ${className}`}
      data-testid="recent-warehouse-orders"
    >
      <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-sm font-semibold text-slate-800">
            Recent orders
          </h2>
          <p className="text-xs text-slate-500">
            {warehouseName || "Selected warehouse"}
          </p>
        </div>
        <Link
          to={`/orders?warehouse_id=${warehouseId}`}
          className="text-sm font-medium text-indigo-600 hover:text-indigo-800"
        >
          View all
        </Link>
      </div>

      {loading && <p className="text-sm text-slate-400">Loading...</p>}
      {error && <p className="text-sm text-rose-600">{error}</p>}
      {!loading && !error && orders.length === 0 && (
        <p className="text-sm text-slate-400">No recent orders</p>
      )}
      {!loading && !error && orders.length > 0 && (
        <div className="divide-y divide-slate-100">
          {orders.map((order) => (
            <Link
              key={order.id}
              to={`/orders/${order.id}`}
              className="grid gap-1 py-2 text-sm hover:bg-slate-50 sm:grid-cols-[1fr_auto] sm:items-center"
            >
              <div>
                <div className="font-medium text-slate-800">
                  {order.order_number}
                </div>
                <div className="text-xs text-slate-500">
                  {order.customer_name || order.customer_email || "No customer"}
                </div>
              </div>
              <div className="text-xs text-slate-500 sm:text-right">
                <div>
                  {order.currency} {Number(order.total_price || 0).toFixed(2)}
                </div>
                <div>
                  {new Date(
                    order.placed_at || order.created_at,
                  ).toLocaleDateString()}
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
