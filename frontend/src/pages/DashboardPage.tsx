import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useSelector } from "react-redux";
import type { RootState } from "../store";
import { productsApi } from "../api/products";
import { ordersApi, type OrderStats } from "../api/orders";

interface Stat {
  label: string;
  value: string;
  hint: string;
  accent: string;
}

export default function DashboardPage() {
  const user = useSelector((s: RootState) => s.auth.user);
  const [productCount, setProductCount] = useState<number | null>(null);
  const [orderStats, setOrderStats] = useState<OrderStats | null>(null);

  useEffect(() => {
    productsApi
      .list({ page: 1, per_page: 1 })
      .then((r) => setProductCount(r.meta.total))
      .catch(() => setProductCount(null));

    ordersApi
      .stats(30)
      .then(setOrderStats)
      .catch(() => setOrderStats(null));
  }, []);

  const revenue30d = orderStats
    ? new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 0,
      }).format(Number(orderStats.total_revenue))
    : "—";

  const stats: Stat[] = [
    {
      label: "Products",
      value: productCount !== null ? productCount.toLocaleString() : "—",
      hint: "in catalog",
      accent: "from-indigo-500 to-purple-600",
    },
    {
      label: "Orders (30d)",
      value: orderStats ? orderStats.count.toLocaleString() : "—",
      hint: orderStats ? `${orderStats.pending_count} pending` : "last 30 days",
      accent: "from-sky-500 to-blue-600",
    },
    {
      label: "Low stock",
      value: "—",
      hint: "Phase 3",
      accent: "from-amber-500 to-orange-600",
    },
    {
      label: "Revenue (30d)",
      value: revenue30d,
      hint: "excl. cancelled",
      accent: "from-emerald-500 to-teal-600",
    },
  ];

  return (
    <div className="space-y-8">
      <div className="rounded-2xl bg-gradient-to-br from-indigo-600 via-indigo-500 to-purple-600 p-6 text-white shadow-sm">
        <h1 className="text-2xl font-semibold">
          Welcome back, {user?.first_name ?? "there"} 👋
        </h1>
        <p className="mt-1 text-indigo-100 text-sm">
          Here&rsquo;s what&rsquo;s happening in your ERP today.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((s) => (
          <div
            key={s.label}
            className="rounded-xl bg-white p-5 shadow-sm border border-gray-100 hover:shadow-md transition"
          >
            <div className="flex items-center justify-between">
              <span className="text-xs uppercase tracking-wider text-gray-500 font-medium">
                {s.label}
              </span>
              <span
                className={`h-2 w-2 rounded-full bg-gradient-to-br ${s.accent}`}
                aria-hidden
              />
            </div>
            <div className="mt-3 text-3xl font-semibold text-gray-900">
              {s.value}
            </div>
            <div className="mt-1 text-xs text-gray-500">{s.hint}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Link
          to="/products"
          className="rounded-xl bg-white p-5 shadow-sm border border-gray-100 hover:shadow-md hover:border-indigo-200 transition group"
        >
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-lg bg-indigo-50 text-indigo-600 flex items-center justify-center">
              <svg
                className="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path d="M4 7h16M4 12h16M4 17h16" strokeLinecap="round" />
              </svg>
            </div>
            <div>
              <div className="font-semibold text-gray-900">Browse products</div>
              <div className="text-xs text-gray-500">
                Search, filter and manage
              </div>
            </div>
          </div>
        </Link>
        <Link
          to="/inventory"
          className="rounded-xl bg-white p-5 shadow-sm border border-gray-100 hover:shadow-md hover:border-amber-200 transition group"
        >
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-lg bg-amber-50 text-amber-600 flex items-center justify-center">
              <svg
                className="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path
                  d="M3 7l9-4 9 4-9 4-9-4zm0 0v10l9 4 9-4V7"
                  strokeLinejoin="round"
                />
              </svg>
            </div>
            <div>
              <div className="font-semibold text-gray-900">Inventory</div>
              <div className="text-xs text-gray-500">
                Warehouses &amp; stock levels
              </div>
            </div>
          </div>
        </Link>
        <Link
          to="/orders"
          className="rounded-xl bg-white p-5 shadow-sm border border-gray-100 hover:shadow-md hover:border-sky-200 transition group"
        >
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-lg bg-sky-50 text-sky-600 flex items-center justify-center">
              <svg
                className="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path d="M3 6h18l-2 12H5L3 6z" strokeLinejoin="round" />
              </svg>
            </div>
            <div>
              <div className="font-semibold text-gray-900">Orders</div>
              <div className="text-xs text-gray-500">
                {orderStats
                  ? `${orderStats.count} in last 30 days`
                  : "View & filter"}
              </div>
            </div>
          </div>
        </Link>
      </div>
    </div>
  );
}
