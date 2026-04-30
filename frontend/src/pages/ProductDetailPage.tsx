import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { productsApi, type Product, type Variant } from "../api/products";

const STATUS_STYLES: Record<string, string> = {
  active: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  draft: "bg-amber-50 text-amber-700 ring-amber-600/20",
  archived: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

function formatMoney(val: string | number | undefined | null) {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  }).format(Number(val ?? 0));
}

export default function ProductDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [product, setProduct] = useState<Product | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeImage, setActiveImage] = useState(0);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    productsApi
      .get(id)
      .then((p) => {
        setProduct(p);
        setActiveImage(0);
      })
      .catch((e) => setError((e as Error).message || "Failed to load"))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading)
    return <div className="p-6 text-sm text-slate-500">Loading product…</div>;
  if (error) return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!product) return null;

  const images = product.images || [];
  const variants: Variant[] = product.variants || [];

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <Link
            to="/products"
            className="text-sm text-slate-500 hover:text-slate-700"
          >
            ← Products
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 mt-1">
            {product.title}
          </h1>
          <div className="flex items-center gap-2 mt-2">
            <span
              className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[product.status] ?? STATUS_STYLES.draft}`}
            >
              {product.status}
            </span>
            {product.shopify_product_id && (
              <span className="inline-flex items-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
                Shopify
              </span>
            )}
            {product.vendor && (
              <span className="text-xs text-slate-500">
                Vendor: {product.vendor}
              </span>
            )}
            {product.product_type && (
              <span className="text-xs text-slate-500">
                · {product.product_type}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left: media + description */}
        <div className="lg:col-span-2 space-y-6">
          {/* Media gallery */}
          {images.length > 0 ? (
            <div className="bg-white border border-slate-200 rounded-xl p-4">
              <img
                src={images[activeImage]?.src}
                alt={images[activeImage]?.alt || product.title}
                className="w-full h-96 object-contain rounded"
              />
              {images.length > 1 && (
                <div className="flex flex-wrap gap-2 mt-3">
                  {images.map((img, idx) => (
                    <button
                      key={img.id || idx}
                      onClick={() => setActiveImage(idx)}
                      className={`h-16 w-16 rounded ring-1 overflow-hidden ${
                        idx === activeImage
                          ? "ring-2 ring-indigo-500"
                          : "ring-slate-200"
                      }`}
                    >
                      <img
                        src={img.src}
                        alt={img.alt || ""}
                        className="h-full w-full object-cover"
                      />
                    </button>
                  ))}
                </div>
              )}
            </div>
          ) : (
            <div className="bg-white border border-slate-200 rounded-xl p-8 text-center text-sm text-slate-400">
              No images
            </div>
          )}

          {/* Description */}
          <div className="bg-white border border-slate-200 rounded-xl p-5">
            <div className="text-xs font-medium text-slate-500 uppercase tracking-wide mb-2">
              Description
            </div>
            {product.description ? (
              <div
                className="prose prose-sm max-w-none text-slate-700"
                dangerouslySetInnerHTML={{ __html: product.description }}
              />
            ) : (
              <div className="text-sm text-slate-400">No description</div>
            )}
          </div>

          {/* Variants */}
          <div className="bg-white border border-slate-200 rounded-xl overflow-hidden">
            <div className="px-4 py-3 border-b border-slate-200 text-sm font-semibold text-slate-900">
              Variants ({variants.length})
            </div>
            {variants.length > 0 ? (
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-xs text-slate-500 uppercase">
                  <tr>
                    <th className="px-4 py-2 text-left">Variant</th>
                    <th className="px-4 py-2 text-left">SKU</th>
                    <th className="px-4 py-2 text-right">Price</th>
                    <th className="px-4 py-2 text-right">Cost</th>
                    <th className="px-4 py-2 text-left">Barcode</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {variants.map((v) => (
                    <tr key={v.id}>
                      <td className="px-4 py-2 text-slate-900">
                        {v.title || "Default"}
                      </td>
                      <td className="px-4 py-2 font-mono text-xs text-slate-600">
                        {v.sku || "—"}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">
                        {formatMoney(v.price)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-slate-600">
                        {v.cost_per_item ? formatMoney(v.cost_per_item) : "—"}
                      </td>
                      <td className="px-4 py-2 font-mono text-xs text-slate-500">
                        {v.barcode || "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="px-4 py-6 text-center text-sm text-slate-400">
                No variants
              </div>
            )}
          </div>
        </div>

        {/* Right: meta */}
        <div className="space-y-4">
          <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
            <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
              Product organization
            </div>
            <div className="text-sm">
              <span className="text-slate-500">Type: </span>
              <span className="text-slate-900">
                {product.product_type || "—"}
              </span>
            </div>
            <div className="text-sm">
              <span className="text-slate-500">Vendor: </span>
              <span className="text-slate-900">{product.vendor || "—"}</span>
            </div>
            <div className="text-sm">
              <span className="text-slate-500">Handle: </span>
              <span className="font-mono text-xs">{product.handle}</span>
            </div>
          </div>

          <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
            <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
              Tags
            </div>
            {product.tags && product.tags.length > 0 ? (
              <div className="flex flex-wrap gap-1">
                {product.tags.map((t) => (
                  <span
                    key={t}
                    className="inline-flex items-center rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                  >
                    {t}
                  </span>
                ))}
              </div>
            ) : (
              <div className="text-sm text-slate-400">No tags</div>
            )}
          </div>

          <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
            <div className="text-xs font-medium text-slate-500 uppercase tracking-wide">
              Search engine listing
            </div>
            <div className="text-sm text-slate-900 font-medium">
              {product.seo_title || product.title}
            </div>
            <div className="text-xs text-slate-500">
              {product.seo_description || "No SEO description"}
            </div>
          </div>

          <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-1 text-xs text-slate-600">
            <div>
              <span className="text-slate-500">Created:</span>{" "}
              {new Date(product.created_at).toLocaleString()}
            </div>
            <div>
              <span className="text-slate-500">Updated:</span>{" "}
              {new Date(product.updated_at).toLocaleString()}
            </div>
            {product.published_at && (
              <div>
                <span className="text-slate-500">Published:</span>{" "}
                {new Date(product.published_at).toLocaleString()}
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="pb-10" />
    </div>
  );
}
