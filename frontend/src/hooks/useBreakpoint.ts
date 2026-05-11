import { useMediaQuery } from "./useMediaQuery";

export type Breakpoint = "mobile" | "tablet" | "desktop";

export function useBreakpoint(): Breakpoint {
  const desktop = useMediaQuery("(min-width: 1024px)");
  const tablet = useMediaQuery("(min-width: 768px)");

  if (desktop) return "desktop";
  if (tablet) return "tablet";
  return "mobile";
}