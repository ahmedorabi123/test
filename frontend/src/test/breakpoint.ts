import { vi } from "vitest";

/**
 * Force `window.matchMedia` to report a given breakpoint so that
 * components which switch between desktop and mobile renderers can
 * be exercised deterministically in jsdom.
 */
export function setBreakpoint(breakpoint: "mobile" | "tablet" | "desktop") {
  const desktop = breakpoint === "desktop";
  const tablet = breakpoint === "tablet" || desktop;
  window.matchMedia = vi.fn().mockImplementation((query: string) => {
    const matches =
      (query.includes("1024") && desktop) ||
      (query.includes("768") && tablet) ||
      false;
    return {
      matches,
      media: query,
      onchange: null,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      addListener: () => undefined,
      removeListener: () => undefined,
      dispatchEvent: () => false,
    } as unknown as MediaQueryList;
  }) as typeof window.matchMedia;
}
