import { ReactNode } from "react";
import { cn } from "../../lib/cn";

export interface FormFieldProps {
  label?: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  required?: boolean;
  children: ReactNode;
  className?: string;
}

export function FormField({
  label,
  hint,
  error,
  required = false,
  children,
  className,
}: FormFieldProps) {
  return (
    <label className={cn("block text-sm", className)}>
      {label && (
        <span className="mb-1 block font-medium text-slate-700">
          {label}
          {required && <span className="text-red-600"> *</span>}
        </span>
      )}
      {children}
      {hint && !error && (
        <span className="mt-1 block text-xs text-slate-500">{hint}</span>
      )}
      {error && (
        <span className="mt-1 block text-xs text-red-600">{error}</span>
      )}
    </label>
  );
}
