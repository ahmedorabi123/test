import { HTMLAttributes } from "react";
import { cn } from "../../lib/cn";

type PageContainerSize = "narrow" | "default" | "wide" | "full";

export interface PageContainerProps extends HTMLAttributes<HTMLDivElement> {
  size?: PageContainerSize;
}

const sizes: Record<PageContainerSize, string> = {
  narrow: "max-w-3xl",
  default: "max-w-7xl",
  wide: "max-w-screen-2xl",
  full: "max-w-none",
};

export function PageContainer({
  className,
  size = "default",
  ...props
}: PageContainerProps) {
  return (
    <div
      className={cn(
        "mx-auto w-full px-4 py-4 sm:px-6 sm:py-6 lg:px-8",
        sizes[size],
        className,
      )}
      {...props}
    />
  );
}
