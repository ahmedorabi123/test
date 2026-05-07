import { useSelector } from "react-redux";
import { useLocation } from "react-router-dom";
import type { RootState } from "../../store";

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
  const match = Object.keys(TITLES).find(
    (k) => k !== "/" && location.pathname.startsWith(k),
  );
  const title = TITLES[location.pathname] ?? (match ? TITLES[match] : "");

  return (
    <header className="h-14 flex items-center justify-between px-6 border-b border-gray-200 bg-white shrink-0">
      <div>
        <h2 className="text-sm font-semibold text-gray-900">{title}</h2>
      </div>
      {user && (
        <div className="flex items-center gap-3">
          <div className="text-right">
            <div className="text-sm font-medium text-gray-800 leading-tight">
              {user.first_name} {user.last_name}
            </div>
            <div className="text-xs text-gray-500 leading-tight">
              {user.email}
            </div>
          </div>
          <div className="h-9 w-9 rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-semibold text-sm shadow-sm">
            {initials(user.first_name, user.last_name, user.email)}
          </div>
        </div>
      )}
    </header>
  );
}
