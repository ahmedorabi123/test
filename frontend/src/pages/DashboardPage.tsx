import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useSelector } from "react-redux";
import type { RootState } from "../store";
import { dashboardApi, type DashboardSummary } from "../api/dashboard";
import { PageContainer } from "../components/ui/PageContainer";

type WindowOpt = 30 | 90;

const STATUS_COLORS: Record<string, string> = {
  pending: "#f59e0b",
  processing: "#3b82f6",
  fulfilled: "#10b981",
  cancelled: "#94a3b8",
  refunded: "#ef4444",
};

const DELIVERY_COLORS: Record<string, string> = {
  pending: "#f59e0b",
  in_transit: "#3b82f6",
  delivered: "#10b981",
  failed: "#ef4444",
};

function fmtCurrency(n: number, currency = "EGP") {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format(n);
}

function fmtNumber(n: number) {
  return new Intl.NumberFormat().format(n);
}

function fmtRelative(iso: string): string {
  const t = new Date(iso).getTime();
  const diff = Date.now() - t;
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const d = Math.floor(hr / 24);
  if (d < 30) return `${d}d ago`;
  return new Date(iso).toLocaleDateString();
}

interface KpiCardProps {
  label: string;
  value: string;
  hint?: string;
  accent: string;
  loading?: boolean;
}
function KpiCard({ label, value, hint, accent, loading }: KpiCardProps) {
  return (
    <div className="relative overflow-hidden rounded-xl border border-gray-100 bg-white p-4 shadow-sm transition hover:shadow-md sm:p-5">
      <div
        className={`absolute inset-y-0 left-0 w-1 bg-gradient-to-b ${accent}`}
        aria-hidden
      />
      <div className="text-xs uppercase tracking-wider text-gray-500 font-medium">
        {label}
      </div>
      <div className="mt-2 text-xl font-semibold text-gray-900 sm:text-2xl">
        {loading ? (
          <span className="inline-block h-7 w-24 bg-gray-200 rounded animate-pulse" />
        ) : (
          value
        )}
      </div>
      {hint && <div className="mt-1 text-xs text-gray-500">{hint}</div>}
    </div>
  );
}

interface RevenueTrendProps {
  data: DashboardSummary["revenue_trend"];
  currency: string;
}
function RevenueTrendChart({ data, currency }: RevenueTrendProps) {
  const W = 800;
  const H = 220;
  const PAD = { l: 50, r: 16, t: 14, b: 26 };
  const max = Math.max(...data.map((d) => d.revenue), 1);
  const xStep = (W - PAD.l - PAD.r) / Math.max(data.length - 1, 1);

  const points = data.map((d, i) => {
    const x = PAD.l + i * xStep;
    const y = PAD.t + (H - PAD.t - PAD.b) * (1 - d.revenue / max);
    return { x, y, ...d };
  });

  const path =
    "M " +
    points
      .map(
        (p, i) => `${i === 0 ? "" : "L "}${p.x.toFixed(1)},${p.y.toFixed(1)}`,
      )
      .join(" ");
  const area =
    `M ${points[0]?.x ?? PAD.l},${H - PAD.b} ` +
    points.map((p) => `L ${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ") +
    ` L ${points[points.length - 1]?.x ?? PAD.l},${H - PAD.b} Z`;

  const yTicks = [0, 0.25, 0.5, 0.75, 1].map((t) => ({
    y: PAD.t + (H - PAD.t - PAD.b) * (1 - t),
    label: fmtCurrency(max * t, currency),
  }));

  const labelEvery = Math.max(1, Math.floor(data.length / 6));

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-48 w-full sm:h-56">
      <defs>
        <linearGradient id="rev-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#6366f1" stopOpacity="0.35" />
          <stop offset="100%" stopColor="#6366f1" stopOpacity="0" />
        </linearGradient>
      </defs>
      {yTicks.map((t, i) => (
        <g key={i}>
          <line x1={PAD.l} x2={W - PAD.r} y1={t.y} y2={t.y} stroke="#f1f5f9" />
          <text
            x={PAD.l - 6}
            y={t.y + 3}
            fontSize="9"
            textAnchor="end"
            fill="#94a3b8"
          >
            {t.label}
          </text>
        </g>
      ))}
      <path d={area} fill="url(#rev-grad)" />
      <path d={path} fill="none" stroke="#6366f1" strokeWidth="2" />
      {points.map((p, i) => (
        <g key={i}>
          {i % labelEvery === 0 && (
            <text
              x={p.x}
              y={H - PAD.b + 14}
              fontSize="9"
              textAnchor="middle"
              fill="#94a3b8"
            >
              {p.date.slice(5)}
            </text>
          )}
          <circle cx={p.x} cy={p.y} r="2.5" fill="#6366f1">
            <title>{`${p.date}: ${fmtCurrency(p.revenue, currency)} · ${p.orders} orders`}</title>
          </circle>
        </g>
      ))}
    </svg>
  );
}

interface DonutDatum {
  label: string;
  value: number;
  color: string;
}
interface DonutProps {
  data: DonutDatum[];
  total: number;
  centerLabel?: string;
  centerValue?: string;
}
function Donut({ data, total, centerLabel, centerValue }: DonutProps) {
  const r = 42;
  const C = 2 * Math.PI * r;
  let offset = 0;
  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-5">
      <svg
        viewBox="0 0 160 160"
        className="h-32 w-32 -rotate-90 sm:h-40 sm:w-40"
      >
        <circle
          cx="80"
          cy="80"
          r={r}
          fill="none"
          stroke="#f1f5f9"
          strokeWidth="16"
        />
        {data.map((d) => {
          const len = total > 0 ? (d.value / total) * C : 0;
          const dash = `${len} ${C - len}`;
          const node = (
            <circle
              key={d.label}
              cx="80"
              cy="80"
              r={r}
              fill="none"
              stroke={d.color}
              strokeWidth="16"
              strokeDasharray={dash}
              strokeDashoffset={-offset}
            />
          );
          offset += len;
          return node;
        })}
        <text
          x="80"
          y="78"
          textAnchor="middle"
          fontSize="10"
          fill="#94a3b8"
          transform="rotate(90 80 80)"
        >
          {centerLabel}
        </text>
        <text
          x="80"
          y="92"
          textAnchor="middle"
          fontSize="16"
          fontWeight="600"
          fill="#1e293b"
          transform="rotate(90 80 80)"
        >
          {centerValue}
        </text>
      </svg>
      <ul className="w-full flex-1 space-y-1.5 text-sm">
        {data.map((d) => (
          <li key={d.label} className="flex items-center justify-between gap-3">
            <span className="flex items-center gap-2 text-gray-700">
              <span
                className="h-2.5 w-2.5 rounded-sm"
                style={{ background: d.color }}
              />
              <span className="capitalize">{d.label.replace(/_/g, " ")}</span>
            </span>
            <span className="font-medium text-gray-900">
              {fmtNumber(d.value)}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

interface MarginGaugeProps {
  margin: number;
  pct: number;
  revenue: number;
  cogs: number;
  currency: string;
}
function MarginGauge({
  margin,
  pct,
  revenue,
  cogs,
  currency,
}: MarginGaugeProps) {
  const clamped = Math.max(0, Math.min(100, pct));
  return (
    <div>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <div className="text-xs uppercase tracking-wider text-gray-500 font-medium">
            Gross margin
          </div>
          <div className="mt-1 text-3xl font-semibold text-gray-900">
            {pct.toFixed(1)}%
          </div>
          <div className="text-xs text-gray-500 mt-0.5">
            {fmtCurrency(margin, currency)} margin
          </div>
        </div>
        <div className="text-xs text-gray-500 sm:text-right">
          <div>Revenue {fmtCurrency(revenue, currency)}</div>
          <div>COGS {fmtCurrency(cogs, currency)}</div>
        </div>
      </div>
      <div className="mt-3 h-2.5 rounded-full bg-gray-100 overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-emerald-500 to-teal-500"
          style={{ width: `${clamped}%` }}
        />
      </div>
    </div>
  );
}

export default function DashboardPage() {
  const user = useSelector((s: RootState) => s.auth.user);
  const [windowDays, setWindowDays] = useState<WindowOpt>(30);
  const [summary, setSummary] = useState<DashboardSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(null);
    dashboardApi
      .summary(windowDays)
      .then((d) => {
        if (alive) setSummary(d);
      })
      .catch((e) => {
        if (alive)
          setError(
            e?.response?.data?.error?.detail ?? "Failed to load dashboard",
          );
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [windowDays]);

  const currency = "EGP";

  const statusDonutData = useMemo<DonutDatum[]>(() => {
    if (!summary) return [];
    return Object.entries(summary.orders_by_status).map(([label, value]) => ({
      label,
      value,
      color: STATUS_COLORS[label] ?? "#64748b",
    }));
  }, [summary]);

  const deliveryDonutData = useMemo<DonutDatum[]>(() => {
    if (!summary) return [];
    return Object.entries(summary.delivery_breakdown).map(([label, value]) => ({
      label,
      value,
      color: DELIVERY_COLORS[label] ?? "#64748b",
    }));
  }, [summary]);

  const ordersTotal = statusDonutData.reduce((a, b) => a + b.value, 0);
  const deliveryTotal = deliveryDonutData.reduce((a, b) => a + b.value, 0);

  return (
    <PageContainer className="space-y-6">
      <div className="flex flex-col gap-4 rounded-2xl bg-gradient-to-br from-slate-900 via-indigo-900 to-slate-900 p-4 text-white shadow-sm sm:flex-row sm:items-end sm:justify-between sm:p-6">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold">
            Welcome back, {user?.first_name ?? "there"}
          </h1>
          <p className="mt-1 text-sm text-indigo-200">
            Operational pulse for the last {windowDays} days.
          </p>
        </div>
        <div className="inline-flex w-fit rounded-lg bg-white/10 p-1 ring-1 ring-white/10">
          {([30, 90] as WindowOpt[]).map((w) => (
            <button
              key={w}
              onClick={() => setWindowDays(w)}
              className={`px-3 py-1.5 text-xs font-medium rounded-md transition ${
                w === windowDays
                  ? "bg-white text-slate-900"
                  : "text-indigo-100 hover:text-white"
              }`}
            >
              {w}d
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 xs:grid-cols-2 md:grid-cols-3 xl:grid-cols-5">
        <KpiCard
          label={`Revenue (${windowDays}d)`}
          value={summary ? fmtCurrency(summary.kpis.revenue, currency) : "—"}
          hint="excl. cancelled"
          accent="from-indigo-500 to-purple-600"
          loading={loading}
        />
        <KpiCard
          label={`Orders (${windowDays}d)`}
          value={summary ? fmtNumber(summary.kpis.orders_count) : "—"}
          hint={summary ? `${summary.kpis.orders_pending} pending` : ""}
          accent="from-sky-500 to-blue-600"
          loading={loading}
        />
        <KpiCard
          label="A/R outstanding"
          value={
            summary ? fmtCurrency(summary.kpis.ar_outstanding, currency) : "—"
          }
          hint="account 1100"
          accent="from-amber-500 to-orange-600"
          loading={loading}
        />
        <KpiCard
          label="Open shipments"
          value={summary ? fmtNumber(summary.kpis.pending_shipments) : "—"}
          hint="pending + in transit"
          accent="from-emerald-500 to-teal-600"
          loading={loading}
        />
        <KpiCard
          label="Low-stock SKUs"
          value={summary ? fmtNumber(summary.kpis.low_stock_count) : "—"}
          hint="at or below threshold"
          accent="from-yellow-500 to-amber-600"
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5 lg:col-span-2">
          <div className="mb-2 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <h2 className="font-semibold text-gray-900">Revenue trend</h2>
            <span className="text-xs text-gray-500">
              Last {windowDays} days
            </span>
          </div>
          {summary ? (
            <RevenueTrendChart
              data={summary.revenue_trend}
              currency={currency}
            />
          ) : (
            <div className="h-56 animate-pulse bg-gray-100 rounded-lg" />
          )}
        </div>
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
          {summary ? (
            <MarginGauge
              margin={summary.gross_margin.margin}
              pct={summary.gross_margin.margin_pct}
              revenue={summary.gross_margin.revenue}
              cogs={summary.gross_margin.cogs}
              currency={currency}
            />
          ) : (
            <div className="h-32 animate-pulse bg-gray-100 rounded-lg" />
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="font-semibold text-gray-900 mb-3">Orders by status</h2>
          {summary && ordersTotal > 0 ? (
            <Donut
              data={statusDonutData}
              total={ordersTotal}
              centerLabel="Total"
              centerValue={fmtNumber(ordersTotal)}
            />
          ) : (
            <div className="text-sm text-gray-500">No orders in window.</div>
          )}
        </div>
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="font-semibold text-gray-900 mb-3">
            Delivery breakdown
          </h2>
          {summary && deliveryTotal > 0 ? (
            <Donut
              data={deliveryDonutData}
              total={deliveryTotal}
              centerLabel="Shipments"
              centerValue={fmtNumber(deliveryTotal)}
            />
          ) : (
            <div className="text-sm text-gray-500">No shipments yet.</div>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="font-semibold text-gray-900">Low-stock alerts</h2>
            <Link
              to="/inventory"
              className="text-xs text-indigo-600 hover:underline"
            >
              View all →
            </Link>
          </div>
          {summary && summary.low_stock.length > 0 ? (
            <ul className="divide-y divide-gray-100">
              {summary.low_stock.map((s) => (
                <li
                  key={s.id}
                  className="flex flex-col gap-2 py-2 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0">
                    <div className="font-medium text-gray-900 truncate">
                      {s.product ?? s.sku ?? s.variant_id}
                    </div>
                    <div className="text-xs text-gray-500 truncate">
                      {s.sku ?? "—"} · {s.warehouse ?? "—"}
                    </div>
                  </div>
                  <div className="shrink-0 sm:ml-3 sm:text-right">
                    <div className="font-semibold text-amber-600">
                      {s.available}
                    </div>
                    <div className="text-[10px] text-gray-400">
                      / {s.threshold}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            <div className="text-sm text-gray-500">
              All stock levels healthy.
            </div>
          )}
        </div>
        <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="font-semibold text-gray-900">
              Top variants ({windowDays}d)
            </h2>
            <Link
              to="/products"
              className="text-xs text-indigo-600 hover:underline"
            >
              All products →
            </Link>
          </div>
          {summary && summary.top_variants.length > 0 ? (
            <ul className="divide-y divide-gray-100">
              {summary.top_variants.map((v, i) => (
                <li
                  key={`${v.variant_id ?? "x"}-${i}`}
                  className="flex flex-col gap-2 py-2 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0">
                    <div className="font-medium text-gray-900 truncate">
                      {v.title}
                    </div>
                    <div className="text-xs text-gray-500 truncate">
                      {v.sku ?? "—"} · {v.quantity} sold
                    </div>
                  </div>
                  <div className="shrink-0 font-semibold text-gray-900 sm:ml-3">
                    {fmtCurrency(v.revenue, currency)}
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            <div className="text-sm text-gray-500">No sales in window.</div>
          )}
        </div>
      </div>

      <div className="rounded-xl border border-gray-100 bg-white p-4 shadow-sm sm:p-5">
        <h2 className="font-semibold text-gray-900 mb-3">Recent activity</h2>
        {summary && summary.recent_activity.length > 0 ? (
          <ul className="space-y-2">
            {summary.recent_activity.map((a, i) => (
              <li key={i} className="flex items-start gap-3 py-1.5">
                <span
                  className={`mt-1 h-2 w-2 shrink-0 rounded-full ${
                    a.kind === "order"
                      ? "bg-sky-500"
                      : a.kind === "shipment"
                        ? "bg-emerald-500"
                        : "bg-rose-500"
                  }`}
                  aria-hidden
                />
                <Link to={a.link} className="flex-1 min-w-0 group">
                  <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between sm:gap-3">
                    <div className="text-sm font-medium text-gray-900 group-hover:text-indigo-600 truncate">
                      {a.title}
                    </div>
                    <div className="text-xs text-gray-400 shrink-0">
                      {fmtRelative(a.at)}
                    </div>
                  </div>
                  <div className="text-xs text-gray-500 truncate">
                    {a.subtitle}
                    {a.amount !== undefined &&
                      ` · ${fmtCurrency(a.amount, a.currency ?? currency)}`}
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <div className="text-sm text-gray-500">No activity yet.</div>
        )}
      </div>
    </PageContainer>
  );
}
