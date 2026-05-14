const apiOrigin = import.meta.env.VITE_API_URL || "http://localhost:3010";

/**
 * Convert a backend-relative URL (e.g. an ActiveStorage blob path) into an
 * absolute URL suitable for an <img src>. Already-absolute URLs are returned
 * unchanged.
 */
export function absoluteMediaUrl(url: string): string {
  if (!url) return url;
  if (/^https?:\/\//.test(url)) return url;
  return `${apiOrigin}${url.startsWith("/") ? url : `/${url}`}`;
}

/**
 * Pick the first available image source for a Product summary record.
 * Falls back from Shopify CDN images (`images`) to ActiveStorage uploaded
 * images so manually created products show their uploads in list views.
 */
export function productThumbnailSrc(product: {
  images?: Array<{ src?: string | null }> | null;
  uploaded_images?: Array<{ url?: string | null }> | null;
}): string | null {
  const cdn = product.images?.[0]?.src;
  if (cdn) return cdn;
  const uploaded = product.uploaded_images?.[0]?.url;
  if (uploaded) return absoluteMediaUrl(uploaded);
  return null;
}
