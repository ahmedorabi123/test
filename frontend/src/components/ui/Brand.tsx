import { BRAND_NAME } from "../../lib/brand";

interface BrandWordmarkProps {
  className?: string;
  /** Optional short tagline rendered under the wordmark */
  tagline?: string;
}

/**
 * Lightweight text wordmark used in the app shell / login screen.
 * Designed to be drop-in replaceable with an SVG logo later.
 */
export function BrandWordmark({ className, tagline }: BrandWordmarkProps) {
  return (
    <div className={className}>
      <span className="text-xl font-semibold tracking-tight text-brand-700">
        {BRAND_NAME}
      </span>
      {tagline && (
        <span className="block text-xs text-slate-500">{tagline}</span>
      )}
    </div>
  );
}

export default BrandWordmark;
