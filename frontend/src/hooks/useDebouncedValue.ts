import { useEffect, useState } from "react";

/**
 * Returns a value that updates `delay` ms after the last input change.
 * Used to keep search input snappy while throttling API calls.
 *
 * Pattern matches the inline debounce already used in InventoryPage; this
 * hook standardises it across modules (Refunds, Suppliers, Collections,
 * Purchases) so search UX is consistent.
 */
export function useDebouncedValue<T>(value: T, delay: number = 300): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(t);
  }, [value, delay]);

  return debounced;
}
