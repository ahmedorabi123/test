import { ButtonHTMLAttributes, ReactNode, forwardRef } from "react";
import { cn } from "../../lib/cn";

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "link";
type ButtonSize = "sm" | "md" | "lg";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: ReactNode;
  iconOnly?: boolean;
  loading?: boolean;
}

const variants: Record<ButtonVariant, string> = {
  primary:
    "border-indigo-600 bg-indigo-600 text-white hover:bg-indigo-700 hover:border-indigo-700 focus:ring-indigo-500",
  secondary:
    "border-slate-300 bg-white text-slate-800 hover:bg-slate-50 focus:ring-slate-400",
  ghost:
    "border-transparent bg-transparent text-slate-700 hover:bg-slate-100 focus:ring-slate-400",
  danger:
    "border-red-600 bg-red-600 text-white hover:bg-red-700 hover:border-red-700 focus:ring-red-500",
  link: "border-transparent bg-transparent text-indigo-700 hover:text-indigo-900 hover:bg-indigo-50 focus:ring-indigo-500",
};

const sizes: Record<ButtonSize, string> = {
  sm: "min-h-9 px-3 text-sm",
  md: "min-h-11 px-4 text-sm",
  lg: "min-h-12 px-5 text-base",
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant = "secondary",
      size = "md",
      icon,
      iconOnly = false,
      loading = false,
      disabled,
      children,
      type = "button",
      ...props
    },
    ref,
  ) => (
    <button
      ref={ref}
      type={type}
      disabled={disabled || loading}
      className={cn(
        "inline-flex shrink-0 items-center justify-center gap-2 rounded-md border font-medium shadow-sm transition focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
        variants[variant],
        iconOnly ? "min-h-11 w-11 px-0" : sizes[size],
        className,
      )}
      {...props}
    >
      {loading && (
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-r-transparent" />
      )}
      {!loading && icon}
      {!iconOnly && children}
    </button>
  ),
);

Button.displayName = "Button";
