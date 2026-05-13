import { createContext, useContext } from "react";

export interface LayoutStateValue {
  sidebarOpen: boolean;
  sidebarCollapsed: boolean;
  setSidebarOpen: (open: boolean) => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  toggleSidebarCollapsed: () => void;
}

export const LayoutStateContext = createContext<LayoutStateValue | null>(null);

export function useLayoutState() {
  const value = useContext(LayoutStateContext);
  if (!value) {
    throw new Error("useLayoutState must be used within LayoutStateProvider");
  }
  return value;
}
