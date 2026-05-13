import { ReactNode, useCallback, useEffect, useMemo, useState } from "react";
import { LayoutStateContext, type LayoutStateValue } from "./layoutState";

export function LayoutStateProvider({ children }: { children: ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsedState] = useState(() => {
    if (typeof window === "undefined") return false;
    return window.localStorage.getItem("erp.sidebarCollapsed") === "true";
  });

  const setSidebarCollapsed = useCallback((collapsed: boolean) => {
    setSidebarCollapsedState(collapsed);
    if (typeof window !== "undefined") {
      window.localStorage.setItem("erp.sidebarCollapsed", String(collapsed));
    }
  }, []);

  const toggleSidebarCollapsed = useCallback(() => {
    setSidebarCollapsed(!sidebarCollapsed);
  }, [setSidebarCollapsed, sidebarCollapsed]);

  useEffect(() => {
    if (typeof window !== "undefined" && window.innerWidth < 1280) {
      setSidebarCollapsedState(true);
    }
  }, []);

  const value = useMemo<LayoutStateValue>(
    () => ({
      sidebarOpen,
      sidebarCollapsed,
      setSidebarOpen,
      setSidebarCollapsed,
      toggleSidebarCollapsed,
    }),
    [
      setSidebarCollapsed,
      sidebarCollapsed,
      sidebarOpen,
      toggleSidebarCollapsed,
    ],
  );

  return (
    <LayoutStateContext.Provider value={value}>
      {children}
    </LayoutStateContext.Provider>
  );
}
