import { useSelector } from "react-redux";
import { useLocation } from "react-router-dom";
import type { RootState } from "../../store";
import { Button } from "../ui/Button";
import { useLayoutState } from "./layoutState";

const TITLES: Record<string, string> = {
  "/": "Dashboard",
  "/products": "Products",
  "/collections": "Collections",
  "/orders": "Orders",
  "/inventory": "Inventory",
  "/customers": "Customers",
  "/purchases": "Purchases",
  "/accounting": "Accounting",
  "/settings": "Settings",
};

function initials(
  first?: string | null,
  last?: string | null,
  email?: string | null,
) {
  const a = (first ?? "").charAt(0);
  const b = (last ?? "").charAt(0);
  const combined = (a + b).trim();
  if (combined) return combined.toUpperCase();
  return (email ?? "?").charAt(0).toUpperCase();
}

export default function Topbar() {
  const user = useSelector((s: RootState) => s.auth.user);
  const location = useLocation();
  const { setSidebarOpen } = useLayoutState();
  const match = Object.keys(TITLES).find(
    (k) => k !== "/" && location.pathname.startsWith(k),
  );
  const title = TITLES[location.pathname] ?? (match ? TITLES[match] : "");

  return (
    <header className="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 sm:px-6">
      <div className="flex min-w-0 items-center gap-2">
        <Button
          variant="ghost"
          iconOnly
          className="lg:hidden"
          aria-label="Open navigation"
          onClick={() => setSidebarOpen(true)}
          icon={
            <svg
              className="h-5 w-5"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2}
              strokeLinecap="round"
            >
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          }
        />
        <h2 className="truncate text-sm font-semibold text-slate-900 sm:text-base">
          {title}
        </h2>
      </div>
      {user && (
        <div className="flex min-w-0 items-center gap-2 sm:gap-3">
          <div className="hidden min-w-0 text-right sm:block">
            <div className="text-sm font-medium leading-tight text-gray-800">
              {user.first_name} {user.last_name}
            </div>
            <div className="max-w-48 truncate text-xs leading-tight text-gray-500 lg:max-w-64">
              {user.email}
            </div>
          </div>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 text-sm font-semibold text-white shadow-sm">
            {initials(user.first_name, user.last_name, user.email)}
          </div>
        </div>
      )}
    </header>
  );
}
