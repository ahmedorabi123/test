import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useMediaQuery } from "./useMediaQuery";

type Listener = (e: { matches: boolean }) => void;

function setupMatchMedia(initialMatches: boolean) {
  const listeners: Listener[] = [];
  const mq = {
    matches: initialMatches,
    media: "",
    onchange: null,
    addEventListener: (_: string, l: Listener) => listeners.push(l),
    removeEventListener: (_: string, l: Listener) => {
      const idx = listeners.indexOf(l);
      if (idx >= 0) listeners.splice(idx, 1);
    },
    addListener: () => undefined,
    removeListener: () => undefined,
    dispatchEvent: () => false,
  } as unknown as MediaQueryList;
  window.matchMedia = vi
    .fn()
    .mockImplementation(() => mq) as typeof window.matchMedia;
  return {
    fire(matches: boolean) {
      (mq as unknown as { matches: boolean }).matches = matches;
      listeners.forEach((l) => l({ matches }));
    },
  };
}

describe("useMediaQuery", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns the initial match value", () => {
    setupMatchMedia(true);
    const { result } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(true);
  });

  it("updates when the media query changes", () => {
    const ctrl = setupMatchMedia(false);
    const { result } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(false);
    act(() => ctrl.fire(true));
    expect(result.current).toBe(true);
  });

  it("returns false when matchMedia is unavailable", () => {
    const original = window.matchMedia;
    // @ts-expect-error – force-remove
    delete window.matchMedia;
    const { result } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(false);
    window.matchMedia = original;
  });
});
