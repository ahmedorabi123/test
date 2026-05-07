import { useEffect, useMemo, useState } from "react";
import { useDebouncedValue } from "../hooks/useDebouncedValue";

export type AsyncComboboxOption = {
  value: string;
  label: string;
  description?: string;
};

type AsyncComboboxProps = {
  selected: AsyncComboboxOption[];
  onChange: (selected: AsyncComboboxOption[]) => void;
  loadOptions: (query: string) => Promise<AsyncComboboxOption[]>;
  placeholder?: string;
  emptyMessage?: string;
  disabled?: boolean;
  className?: string;
};

export default function AsyncCombobox({
  selected,
  onChange,
  loadOptions,
  placeholder = "Search...",
  emptyMessage = "No results",
  disabled = false,
  className = "",
}: AsyncComboboxProps) {
  const [input, setInput] = useState("");
  const [open, setOpen] = useState(false);
  const [options, setOptions] = useState<AsyncComboboxOption[]>([]);
  const [loading, setLoading] = useState(false);
  const debouncedInput = useDebouncedValue(input, 300);

  useEffect(() => {
    if (!open || disabled) return;

    let active = true;
    setLoading(true);
    loadOptions(debouncedInput.trim())
      .then((rows) => {
        if (active) setOptions(rows);
      })
      .catch(() => {
        if (active) setOptions([]);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [debouncedInput, disabled, loadOptions, open]);

  const selectedIds = useMemo(
    () => new Set(selected.map((option) => option.value)),
    [selected],
  );
  const visibleOptions = options.filter((option) => !selectedIds.has(option.value));

  const remove = (value: string) => {
    onChange(selected.filter((option) => option.value !== value));
  };

  const choose = (option: AsyncComboboxOption) => {
    if (selectedIds.has(option.value)) return;
    onChange([...selected, option]);
    setInput("");
    setOpen(true);
  };

  return (
    <div className={`relative ${className}`}>
      {selected.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-1.5">
          {selected.map((option) => (
            <span
              key={option.value}
              className="inline-flex items-center gap-1 rounded-md bg-slate-100 px-2 py-1 text-xs font-medium text-slate-700"
            >
              {option.label}
              <button
                type="button"
                aria-label={`Remove ${option.label}`}
                onClick={() => remove(option.value)}
                className="rounded px-1 text-slate-500 hover:bg-slate-200 hover:text-slate-700"
              >
                x
              </button>
            </span>
          ))}
        </div>
      )}

      <input
        type="text"
        value={input}
        disabled={disabled}
        onChange={(event) => setInput(event.target.value)}
        onFocus={() => setOpen(true)}
        onBlur={() => window.setTimeout(() => setOpen(false), 120)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50"
      />

      {open && !disabled && (
        <div className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-lg border border-slate-200 bg-white shadow-lg">
          {loading && (
            <div className="px-3 py-2 text-sm text-slate-400">Loading...</div>
          )}
          {!loading && visibleOptions.length === 0 && (
            <div className="px-3 py-2 text-sm text-slate-400">
              {emptyMessage}
            </div>
          )}
          {!loading &&
            visibleOptions.map((option) => (
              <button
                type="button"
                key={option.value}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => choose(option)}
                className="block w-full px-3 py-2 text-left text-sm hover:bg-indigo-50"
              >
                <span className="block font-medium text-slate-800">
                  {option.label}
                </span>
                {option.description && (
                  <span className="block text-xs text-slate-500">
                    {option.description}
                  </span>
                )}
              </button>
            ))}
        </div>
      )}
    </div>
  );
}
