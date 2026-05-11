import { TextareaHTMLAttributes, forwardRef } from "react";
import { cn } from "../../lib/cn";

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  invalid?: boolean;
}

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, invalid = false, rows = 4, ...props }, ref) => (
    <textarea
      ref={ref}
      rows={rows}
      className={cn(
        "block w-full rounded-md border bg-white px-3 py-2 text-sm text-slate-900 shadow-sm transition placeholder:text-slate-400 focus:outline-none focus:ring-2 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500 min-h-11",
        invalid
          ? "border-red-300 focus:border-red-500 focus:ring-red-500"
          : "border-slate-300 focus:border-indigo-500 focus:ring-indigo-500",
        className,
      )}
      {...props}
    />
  ),
);

Textarea.displayName = "Textarea";