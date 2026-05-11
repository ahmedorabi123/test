import { ReactNode, useEffect } from "react";
import { createPortal } from "react-dom";
import { cn } from "../../lib/cn";

type DrawerSide = "left" | "right";
type DrawerSize = "sm" | "md" | "lg";

export interface DrawerProps {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  side?: DrawerSide;
  size?: DrawerSize;
  className?: string;
  labelledBy?: string;
}

const sideClasses: Record<DrawerSide, string> = {
  left: "left-0",
  right: "right-0",
};

const sizeClasses: Record<DrawerSize, string> = {
  sm: "max-w-xs",
  md: "max-w-sm",
  lg: "max-w-md",
};

export function Drawer({
  open,
  onClose,
  children,
  side = "left",
  size = "md",
  className,
  labelledBy,
}: DrawerProps) {
  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [onClose, open]);

  if (!open) return null;

  return createPortal(
    <div className="fixed inset-0 z-50 lg:hidden">
      <button
        type="button"
        aria-label="Close navigation"
        className="absolute inset-0 h-full w-full cursor-default bg-slate-950/50"
        onClick={onClose}
      />
      <aside
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelledBy}
        className={cn(
          "absolute top-0 flex h-full w-[min(90vw,22rem)] flex-col overflow-y-auto bg-white shadow-xl",
          sideClasses[side],
          sizeClasses[size],
          className,
        )}
      >
        {children}
      </aside>
    </div>,
    document.body,
  );
}