import { useEffect } from "react";
import Sidebar from "./Sidebar";
import Topbar from "./Topbar";
import { Outlet, useLocation } from "react-router-dom";
import { Drawer } from "../ui/Drawer";
import { useMediaQuery } from "../../hooks/useMediaQuery";
import { LayoutStateProvider } from "./LayoutStateContext";
import { useLayoutState } from "./layoutState";

export default function AppLayout() {
  return (
    <LayoutStateProvider>
      <AppLayoutShell />
    </LayoutStateProvider>
  );
}

function AppLayoutShell() {
  const location = useLocation();
  const { sidebarOpen, sidebarCollapsed, setSidebarOpen } = useLayoutState();
  const autoCompact = useMediaQuery(
    "(min-width: 1024px) and (max-width: 1279px)",
  );
  const collapsed = sidebarCollapsed || autoCompact;

  useEffect(() => {
    setSidebarOpen(false);
  }, [location.pathname, setSidebarOpen]);

  return (
    <div className="flex h-dvh min-w-0 overflow-hidden bg-slate-50">
      <div className="hidden lg:flex">
        <Sidebar collapsed={collapsed} />
      </div>
      <Drawer
        open={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        className="bg-slate-950 p-0 text-slate-100"
        labelledBy="mobile-navigation-title"
      >
        <Sidebar mobile onNavigate={() => setSidebarOpen(false)} />
      </Drawer>
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <Topbar />
        <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 lg:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
