import { SelectHTMLAttributes, forwardRef } from "react";
import { cn } from "../../lib/cn";

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  invalid?: boolean;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, invalid = false, ...props }, ref) => (
    <select
      ref={ref}
      className={cn(
        "block w-full rounded-md border bg-white px-3 py-2 text-sm text-slate-900 shadow-sm transition focus:outline-none focus:ring-2 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500 min-h-11",
        invalid
          ? "border-red-300 focus:border-red-500 focus:ring-red-500"
          : "border-slate-300 focus:border-indigo-500 focus:ring-indigo-500",
        className,
      )}
      {...props}
    />
  ),
);

Select.displayName = "Select";
