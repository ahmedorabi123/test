import { ReactNode } from "react";
import { cn } from "../../lib/cn";

export interface TabItem<T extends string> {
  id: T;
  label: ReactNode;
  badge?: ReactNode;
}

export interface TabsProps<T extends string> {
  tabs: Array<TabItem<T>>;
  value: T;
  onChange: (value: T) => void;
  className?: string;
}

export function Tabs<T extends string>({
  tabs,
  value,
  onChange,
  className,
}: TabsProps<T>) {
  return (
    <div className={cn("-mx-1 overflow-x-auto px-1", className)}>
      <div
        role="tablist"
        className="flex min-w-max gap-1 border-b border-slate-200"
      >
        {tabs.map((tab) => {
          const active = tab.id === value;
          return (
            <button
              key={tab.id}
              role="tab"
              type="button"
              aria-selected={active}
              onClick={() => onChange(tab.id)}
              className={cn(
                "inline-flex min-h-11 items-center gap-2 border-b-2 px-3 py-2 text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
                active
                  ? "border-indigo-600 text-indigo-700"
                  : "border-transparent text-slate-500 hover:border-slate-300 hover:text-slate-800",
              )}
            >
              {tab.label}
              {tab.badge}
            </button>
          );
        })}
      </div>
    </div>
  );
}
