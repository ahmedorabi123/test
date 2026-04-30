import { Link, useLocation } from "react-router-dom";
import { useDispatch, useSelector } from "react-redux";
import type { AppDispatch, RootState } from "../../store";
import { logout } from "../../store/slices/authSlice";

type NavItem = {
  label: string;
  path: string;
  icon: React.ReactNode;
  phase?: "live" | "soon";
  resource?: string; // RBAC gating: hidden unless user has "<resource>:read" or is admin
};

const Icon = ({ d }: { d: string }) => (
  <svg
    className="h-[18px] w-[18px] shrink-0"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={1.8}
    strokeLinecap="round"
    strokeLinejoin="round"
  >
    <path d={d} />
  </svg>
);

const navItems: NavItem[] = [
  {
    label: "Dashboard",
    path: "/",
    icon: <Icon d="M3 12l9-9 9 9M5 10v10h14V10" />,
    phase: "live",
  },
  {
    label: "Products",
    path: "/products",
    icon: <Icon d="M4 7h16M4 12h16M4 17h16" />,
    phase: "live",
    resource: "products",
  },
  {
    label: "Orders",
    path: "/orders",
    icon: (
      <Icon d="M3 6h18l-2 12H5L3 6zm4 0V4a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v2" />
    ),
    phase: "live",
    resource: "orders",
  },
  {
    label: "Inventory",
    path: "/inventory",
    icon: <Icon d="M3 7l9-4 9 4-9 4-9-4zm0 0v10l9 4 9-4V7" />,
    phase: "live",
    resource: "inventory",
  },
  {
    label: "Warehouses",
    path: "/warehouses",
    icon: <Icon d="M3 21V8l9-5 9 5v13M9 21V12h6v9" />,
    phase: "live",
    resource: "inventory",
  },
  {
    label: "Customers",
    path: "/customers",
    icon: (
      <Icon d="M17 20v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm4 9v-1a3 3 0 0 0-2-2.83" />
    ),
    phase: "live",
    resource: "customers",
  },
  {
    label: "Shipments",
    path: "/shipments",
    icon: (
      <Icon d="M3 7h13v10H3zM16 10h5l2 3v4h-7zM6 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm12 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4z" />
    ),
    phase: "live",
    resource: "fulfillments",
  },
  {
    label: "Refunds",
    path: "/refunds",
    icon: <Icon d="M3 7v6h6M3 13a9 9 0 1 0 3-6.708" />,
    phase: "live",
    resource: "orders",
  },
  {
    label: "Purchases",
    path: "/purchases",
    icon: (
      <Icon d="M9 2v4M15 2v4M3 10h18M5 6h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z" />
    ),
    phase: "live",
    resource: "purchase_orders",
  },
  {
    label: "Suppliers",
    path: "/suppliers",
    icon: <Icon d="M3 6h18M3 12h18M3 18h18" />,
    phase: "live",
    resource: "suppliers",
  },
  {
    label: "Accounting",
    path: "/accounting",
    icon: <Icon d="M4 4h16v4H4zM4 12h10v8H4zM18 12h2v8h-2z" />,
    phase: "live",
    resource: "accounting",
  },
  {
    label: "Production",
    path: "/production",
    icon: <Icon d="M4 20h16M4 20V10l8-6 8 6v10M9 20v-6h6v6" />,
    phase: "live",
    resource: "production_orders",
  },
  {
    label: "Audit logs",
    path: "/audit_logs",
    icon: <Icon d="M4 4h16v16H4zM8 8h8M8 12h8M8 16h5" />,
    phase: "live",
    resource: "audit_log",
  },
  {
    label: "Users & Roles",
    path: "/users",
    icon: (
      <Icon d="M16 11a4 4 0 1 0-8 0 4 4 0 0 0 8 0zM4 21v-2a4 4 0 0 1 4-4h8a4 4 0 0 1 4 4v2" />
    ),
    phase: "live",
    resource: "user",
  },
  {
    label: "Settings",
    path: "/settings",
    icon: <Icon d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z" />,
    phase: "soon",
  },
];

export default function Sidebar() {
  const location = useLocation();
  const dispatch = useDispatch<AppDispatch>();
  const user = useSelector((s: RootState) => s.auth.user);

  const isAdmin = user?.roles?.includes("admin");
  const permissions = user?.permissions ?? [];
  const canSee = (item: NavItem): boolean => {
    if (!item.resource) return true;
    if (isAdmin) return true;
    return permissions.includes(`${item.resource}:read`);
  };
  const visibleItems = navItems.filter(canSee);

  return (
    <aside className="flex flex-col w-60 min-h-screen bg-gradient-to-b from-slate-900 via-slate-900 to-slate-950 text-slate-100 py-6 px-3 shrink-0 border-r border-slate-800">
      <div className="flex items-center gap-2 px-3 mb-8">
        <div className="h-8 w-8 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
          E
        </div>
        <div>
          <div className="text-sm font-semibold leading-tight">Shopify ERP</div>
          <div className="text-[10px] text-slate-400 uppercase tracking-wider">
            Console
          </div>
        </div>
      </div>
      <nav className="flex-1 space-y-0.5">
        {visibleItems.map((item) => {
          const active =
            item.path === "/"
              ? location.pathname === "/"
              : location.pathname.startsWith(item.path);
          return (
            <Link
              key={item.path}
              to={item.path}
              className={`group flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-all ${
                active
                  ? "bg-indigo-500/15 text-white ring-1 ring-inset ring-indigo-400/30"
                  : "text-slate-400 hover:bg-slate-800/60 hover:text-white"
              }`}
            >
              <span
                className={
                  active
                    ? "text-indigo-300"
                    : "text-slate-500 group-hover:text-slate-300"
                }
              >
                {item.icon}
              </span>
              <span className="flex-1">{item.label}</span>
              {item.phase === "soon" && (
                <span className="text-[9px] font-medium uppercase tracking-wider text-slate-500 bg-slate-800 px-1.5 py-0.5 rounded">
                  Soon
                </span>
              )}
            </Link>
          );
        })}
      </nav>
      <button
        onClick={() => dispatch(logout())}
        className="mt-4 flex items-center gap-2 px-3 py-2 text-sm text-slate-400 hover:text-white hover:bg-slate-800/60 rounded-lg transition"
      >
        <Icon d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H5a3 3 0 01-3-3V7a3 3 0 013-3h5a3 3 0 013 3v1" />
        <span>Sign out</span>
      </button>
    </aside>
  );
}
