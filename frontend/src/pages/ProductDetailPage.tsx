import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { collectionsApi } from "../api/collections";
import {
  productsApi,
  type Product,
  type ProductMetafield,
  type Variant,
} from "../api/products";
import AsyncCombobox, {
  type AsyncComboboxOption,
} from "../components/AsyncCombobox";
import { htmlToText } from "../lib/htmlText";

const STATUS_STYLES: Record<string, string> = {
  active: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  draft: "bg-amber-50 text-amber-700 ring-amber-600/20",
  archived: "bg-gray-100 text-gray-600 ring-gray-500/20",
};

const CATEGORY_METAFIELDS = [
  { key: "color", label: "Color" },
  { key: "size", label: "Size" },
  { key: "fabric", label: "Fabric" },
  { key: "age_group", label: "Age group" },
  { key: "neckline", label: "Neckline" },
  { key: "sleeve_length", label: "Sleeve length" },
  { key: "target_gender", label: "Target gender" },
  { key: "material", label: "Material" },
];

// Full variant draft type — mirrors all editable fields
type VariantDraft = {
  /** undefined = new (not yet saved) */
  id?: string;
  title: string;
  sku: string;
  price: string;
  compare_at_price: string;
  cost_per_item: string;
  barcode: string;
  weight: string;
  weight_unit: "kg" | "g" | "lb" | "oz";
  inventory_policy: "deny" | "continue";
  requires_shipping: boolean;
  taxable: boolean;
  hs_code: string;
  country_of_origin: string;
  /** UI only: show extra fields row */
  _expanded: boolean;
  /** Rails nested-attributes destroy flag */
  _destroy: boolean;
};

const BLANK_VARIANT: VariantDraft = {
  title: "Default",
  sku: "",
  price: "0.00",
  compare_at_price: "",
  cost_per_item: "",
  barcode: "",
  weight: "",
  weight_unit: "kg",
  inventory_policy: "deny",
  requires_shipping: true,
  taxable: true,
  hs_code: "",
  country_of_origin: "",
  _expanded: false,
  _destroy: false,
};

type Draft = Pick<
  Product,
  | "title"
  | "handle"
  | "description"
  | "status"
  | "vendor"
  | "product_type"
  | "tags"
  | "seo_title"
  | "seo_description"
  | "published_at"
  | "published_scope"
> & {
  collection_ids: string[];
  variants_draft: VariantDraft[];
  metafields_draft: ProductMetafield[];
};

function collectionOptions(product: Product): AsyncComboboxOption[] {
  return (product.collections ?? []).map((collection) => ({
    value: collection.id,
    label: collection.title,
    description: collection.handle ? `/${collection.handle}` : undefined,
  }));
}

function variantToJson(v: Variant): VariantDraft {
  return {
    id: v.id,
    title: v.title,
    sku: v.sku ?? "",
    price: String(v.price),
    compare_at_price: v.compare_at_price ? String(v.compare_at_price) : "",
    cost_per_item: (v.cost_per_item ?? v.cost)
      ? String(v.cost_per_item ?? v.cost)
      : "",
    barcode: v.barcode ?? "",
    weight: v.weight ? String(v.weight) : "",
    weight_unit: (v.weight_unit ?? "kg") as VariantDraft["weight_unit"],
    inventory_policy: (v.inventory_policy ??
      "deny") as VariantDraft["inventory_policy"],
    requires_shipping: v.requires_shipping ?? true,
    taxable: v.taxable ?? true,
    hs_code: v.hs_code ?? "",
    country_of_origin: v.country_of_origin ?? "",
    _expanded: false,
    _destroy: false,
  };
}

function toDraft(p: Product): Draft {
  return {
    title: p.title,
    handle: p.handle,
    description: htmlToText(p.description ?? ""),
    status: p.status,
    vendor: p.vendor ?? "",
    product_type: p.product_type ?? "",
    tags: [...(p.tags ?? [])],
    seo_title: p.seo_title ?? "",
    seo_description: p.seo_description ?? "",
    published_at: p.published_at ?? "",
    published_scope: p.published_scope ?? "web",
    collection_ids:
      p.collection_ids ?? (p.collections ?? []).map((collection) => collection.id),
    variants_draft: (p.variants ?? []).map(variantToJson),
    metafields_draft: [...(p.metafields ?? [])],
  };
}

export default function ProductDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [product, setProduct] = useState<Product | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const originalRef = useRef<string>("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeImage, setActiveImage] = useState(0);
  const [tagInput, setTagInput] = useState("");
  const [selectedCollections, setSelectedCollections] = useState<
    AsyncComboboxOption[]
  >([]);

  const loadCollectionOptions = useCallback(async (query: string) => {
    const rows = await collectionsApi.list({
      kind: "custom",
      per_page: 20,
      search: query || undefined,
      sort: "title",
      dir: "asc",
    });
    return rows.data.map((collection) => ({
      value: collection.id,
      label: collection.title,
      description: collection.handle ? `/${collection.handle}` : undefined,
    }));
  }, []);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    productsApi
      .get(id)
      .then((p) => {
        setProduct(p);
        const d = toDraft(p);
        setDraft(d);
        setSelectedCollections(collectionOptions(p));
        originalRef.current = JSON.stringify(d);
      })
      .catch((e) => setError((e as Error).message || "Failed to load"))
      .finally(() => setLoading(false));
  }, [id]);

  const isDirty = draft ? JSON.stringify(draft) !== originalRef.current : false;

  async function handleSave() {
    if (!product || !draft) return;
    setSaving(true);
    setError(null);
    try {
      const payload: Parameters<typeof productsApi.update>[1] = {
        title: draft.title,
        handle: draft.handle,
        description: draft.description,
        status: draft.status,
        vendor: draft.vendor || null,
        product_type: draft.product_type || null,
        tags: draft.tags,
        seo_title: draft.seo_title || null,
        seo_description: draft.seo_description || null,
        published_at: draft.published_at || null,
        published_scope: draft.published_scope,
        collection_ids: draft.collection_ids,
        metafields: draft.metafields_draft.filter(
          (row) => row.namespace.trim() && row.key.trim(),
        ),
        variants_attributes: draft.variants_draft.map((v, idx) => {
          const base: Record<string, unknown> = {
            sku: v.sku.trim() || null,
            title: v.title.trim(),
            price: v.price,
            compare_at_price: v.compare_at_price.trim() || null,
            cost: v.cost_per_item.trim() || null,
            cost_per_item: v.cost_per_item.trim() || null,
            barcode: v.barcode.trim() || null,
            weight: v.weight.trim() || null,
            weight_unit: v.weight_unit,
            inventory_policy: v.inventory_policy,
            requires_shipping: v.requires_shipping,
            taxable: v.taxable,
            hs_code: v.hs_code.trim() || null,
            country_of_origin: v.country_of_origin.trim() || null,
            position: idx + 1,
          };
          if (v.id) base.id = v.id;
          if (v._destroy) base._destroy = true;
          return base;
        }),
      };
      const updated = await productsApi.update(product.id, payload);
      setProduct(updated);
      const d = toDraft(updated);
      setDraft(d);
      setSelectedCollections(collectionOptions(updated));
      originalRef.current = JSON.stringify(d);
    } catch (e) {
      setError((e as Error).message || "Save failed");
    } finally {
      setSaving(false);
    }
  }

  function handleDiscard() {
    if (!product) return;
    const d = toDraft(product);
    setDraft(d);
    setSelectedCollections(collectionOptions(product));
    originalRef.current = JSON.stringify(d);
  }

  const setDraftField = (
    field: keyof Omit<Draft, "variants_draft">,
    value: unknown,
  ) => {
    setDraft((prev) => (prev ? { ...prev, [field]: value } : prev));
  };

  // For updateVariant, idx is the index in the FULL variants_draft array (including _destroy items)
  const updateVariant = (idx: number, patch: Partial<VariantDraft>) => {
    setDraft((prev) => {
      if (!prev) return prev;
      const vd = [...prev.variants_draft];
      vd[idx] = { ...vd[idx], ...patch };
      return { ...prev, variants_draft: vd };
    });
  };

  const addVariant = () => {
    setDraft((prev) => {
      if (!prev) return prev;
      const visibleCount = prev.variants_draft.filter(
        (v) => !v._destroy,
      ).length;
      return {
        ...prev,
        variants_draft: [
          ...prev.variants_draft,
          { ...BLANK_VARIANT, title: `Variant ${visibleCount + 1}` },
        ],
      };
    });
  };

  const removeVariant = (idx: number) => {
    setDraft((prev) => {
      if (!prev) return prev;
      const vd = [...prev.variants_draft];
      const v = vd[idx];
      if (v.id) {
        // Existing variant — mark for Rails to destroy
        vd[idx] = { ...v, _destroy: true };
      } else {
        // New (unsaved) variant — just splice out
        vd.splice(idx, 1);
      }
      return { ...prev, variants_draft: vd };
    });
  };

  const setMetafieldValue = (
    namespace: string,
    key: string,
    value: string,
    type = "single_line_text_field",
  ) => {
    setDraft((prev) => {
      if (!prev) return prev;
      const existingIndex = prev.metafields_draft.findIndex(
        (row) => row.namespace === namespace && row.key === key,
      );
      const next = [...prev.metafields_draft];
      if (existingIndex >= 0) {
        next[existingIndex] = { ...next[existingIndex], type, value };
      } else {
        next.push({ namespace, key, type, value });
      }
      return { ...prev, metafields_draft: next };
    });
  };

  const updateCustomMetafield = (
    idx: number,
    patch: Partial<ProductMetafield>,
  ) => {
    setDraft((prev) => {
      if (!prev) return prev;
      const customIndexes = prev.metafields_draft.reduce<number[]>(
        (acc, row, rowIdx) => {
          if (row.namespace !== "category") acc.push(rowIdx);
          return acc;
        },
        [],
      );
      const rowIdx = customIndexes[idx];
      const next = [...prev.metafields_draft];
      next[rowIdx] = { ...next[rowIdx], ...patch };
      return { ...prev, metafields_draft: next };
    });
  };

  const addCustomMetafield = () => {
    setDraft((prev) =>
      prev
        ? {
            ...prev,
            metafields_draft: [
              ...prev.metafields_draft,
              {
                namespace: "custom",
                key: "",
                type: "single_line_text_field",
                value: "",
              },
            ],
          }
        : prev,
    );
  };

  const removeCustomMetafield = (idx: number) => {
    setDraft((prev) => {
      if (!prev) return prev;
      const customIndexes = prev.metafields_draft.reduce<number[]>(
        (acc, row, rowIdx) => {
          if (row.namespace !== "category") acc.push(rowIdx);
          return acc;
        },
        [],
      );
      const rowIdx = customIndexes[idx];
      return {
        ...prev,
        metafields_draft: prev.metafields_draft.filter(
          (_, currentIdx) => currentIdx !== rowIdx,
        ),
      };
    });
  };

  if (loading)
    return <div className="p-6 text-sm text-slate-500">Loading product…</div>;
  if (error && !product)
    return <div className="p-6 text-sm text-rose-600">{error}</div>;
  if (!product || !draft) return null;

  const images = product.images || [];

  return (
    <div className="max-w-7xl mx-auto pb-24">
      {/* Sticky save bar */}
      {isDirty && (
        <div className="sticky top-0 z-30 bg-amber-50 border-b border-amber-200 px-6 py-3 flex items-center gap-4 shadow-sm">
          <span className="text-sm text-amber-800 font-medium flex-1">
            You have unsaved changes
          </span>
          <button
            onClick={handleDiscard}
            className="rounded-lg border border-slate-300 bg-white px-4 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
          >
            Discard
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="rounded-lg bg-indigo-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {saving ? "Saving…" : "Save changes"}
          </button>
        </div>
      )}

      {/* Header */}
      <div className="flex items-start justify-between mt-4 mb-6 px-1">
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
              className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${STATUS_STYLES[draft.status] ?? STATUS_STYLES.draft}`}
            >
              {draft.status}
            </span>
            {product.shopify_product_id && (
              <span className="inline-flex items-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20 px-2 py-0.5 text-xs font-medium">
                Shopify
              </span>
            )}
          </div>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => {
              if (!window.confirm("Archive this product?")) return;
              productsApi
                .update(product.id, { status: "archived" })
                .then((p) => {
                  setProduct(p);
                  const d = toDraft(p);
                  setDraft(d);
                  originalRef.current = JSON.stringify(d);
                });
            }}
            className="rounded-lg border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-50"
          >
            Archive
          </button>
          <button
            onClick={async () => {
              if (
                !window.confirm("Delete this product? This cannot be undone.")
              )
                return;
              try {
                await productsApi.destroy(product.id);
                navigate("/products");
              } catch {
                // If delete archived, we may have gotten a 200 instead
                navigate("/products");
              }
            }}
            className="rounded-lg border border-red-300 bg-red-50 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-100"
          >
            Delete
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left col */}
        <div className="lg:col-span-2 space-y-4">
          {/* Title + Description */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-5 space-y-4">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Title &amp; Description
            </h2>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Title
              </label>
              <input
                value={draft.title}
                onChange={(e) => setDraftField("title", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Description
              </label>
              <textarea
                rows={6}
                value={draft.description ?? ""}
                onChange={(e) => setDraftField("description", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
          </div>

          {/* Media gallery (read-only — managed via Shopify) */}
          {images.length > 0 && (
            <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4">
              <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">
                Media
              </h2>
              <img
                src={images[activeImage]?.src}
                alt={images[activeImage]?.alt || product.title}
                className="w-full max-h-80 object-contain rounded"
              />
              {images.length > 1 && (
                <div className="flex flex-wrap gap-2 mt-3">
                  {images.map((img, idx) => (
                    <button
                      key={img.id || idx}
                      onClick={() => setActiveImage(idx)}
                      className={`h-14 w-14 rounded ring-1 overflow-hidden ${idx === activeImage ? "ring-2 ring-indigo-500" : "ring-slate-200"}`}
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
          )}

          {/* Variants */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 overflow-hidden">
            <div className="px-5 py-3 border-b border-slate-200 flex items-center justify-between">
              <span className="text-sm font-semibold text-slate-900">
                Variants (
                {draft.variants_draft.filter((v) => !v._destroy).length})
              </span>
              <button
                type="button"
                onClick={addVariant}
                className="text-xs font-medium text-indigo-600 hover:text-indigo-500"
              >
                + Add variant
              </button>
            </div>
            {draft.variants_draft.filter((v) => !v._destroy).length > 0 ? (
              <div className="divide-y divide-slate-100">
                {draft.variants_draft.map((v, idx) => {
                  if (v._destroy) return null;
                  // Stock items come from the live product data (not the draft)
                  const liveVariant = (product.variants ?? []).find(
                    (lv) => lv.id === v.id,
                  );
                  const stockItems = liveVariant?.stock_items ?? [];
                  const totalStock = stockItems.reduce(
                    (sum, si) => sum + si.quantity_on_hand,
                    0,
                  );
                  return (
                    <div key={v.id ?? `new-${idx}`} className="p-4 space-y-3">
                      {/* Row 1: title, sku, price, compare, inventory */}
                      <div className="grid grid-cols-12 gap-2 items-start">
                        {/* Title */}
                        <div className="col-span-3">
                          <label className="block text-[10px] font-medium text-slate-500 mb-1">
                            Title
                          </label>
                          <input
                            value={v.title}
                            onChange={(e) =>
                              updateVariant(idx, { title: e.target.value })
                            }
                            placeholder="e.g. Black / M"
                            className="w-full rounded border border-slate-200 px-2 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-400"
                          />
                        </div>
                        {/* SKU */}
                        <div className="col-span-2">
                          <label className="block text-[10px] font-medium text-slate-500 mb-1">
                            SKU
                          </label>
                          <input
                            value={v.sku}
                            onChange={(e) =>
                              updateVariant(idx, { sku: e.target.value })
                            }
                            placeholder="SKU"
                            className="w-full rounded border border-slate-200 px-2 py-1.5 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-indigo-400"
                          />
                        </div>
                        {/* Price */}
                        <div className="col-span-2">
                          <label className="block text-[10px] font-medium text-slate-500 mb-1">
                            Price
                          </label>
                          <input
                            value={v.price}
                            onChange={(e) =>
                              updateVariant(idx, { price: e.target.value })
                            }
                            placeholder="0.00"
                            type="number"
                            step="0.01"
                            min="0"
                            className="w-full rounded border border-slate-200 px-2 py-1.5 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-indigo-400"
                          />
                        </div>
                        {/* Compare at */}
                        <div className="col-span-2">
                          <label className="block text-[10px] font-medium text-slate-500 mb-1">
                            Compare at
                          </label>
                          <input
                            value={v.compare_at_price}
                            onChange={(e) =>
                              updateVariant(idx, {
                                compare_at_price: e.target.value,
                              })
                            }
                            placeholder="—"
                            type="number"
                            step="0.01"
                            min="0"
                            className="w-full rounded border border-slate-200 px-2 py-1.5 text-xs text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-indigo-400"
                          />
                        </div>
                        {/* Inventory */}
                        <div className="col-span-2">
                          <label className="block text-[10px] font-medium text-slate-500 mb-1">
                            Inventory
                          </label>
                          {v.id ? (
                            stockItems.length > 0 ? (
                              <div className="space-y-0.5">
                                {stockItems.map((si) => (
                                  <div
                                    key={si.id}
                                    className="flex items-center justify-between text-xs"
                                  >
                                    <span className="text-slate-500 truncate max-w-[80px]">
                                      {si.warehouse_name}
                                    </span>
                                    <span
                                      className={`font-medium tabular-nums ${si.quantity_on_hand > 0 ? "text-emerald-700" : "text-slate-400"}`}
                                    >
                                      {si.quantity_on_hand}
                                    </span>
                                  </div>
                                ))}
                                <div className="border-t border-slate-100 pt-0.5 flex justify-between text-[10px]">
                                  <span className="text-slate-400">Total</span>
                                  <span className="font-semibold text-slate-700 tabular-nums">
                                    {totalStock}
                                  </span>
                                </div>
                              </div>
                            ) : (
                              <span className="text-xs text-slate-400">
                                Not tracked
                              </span>
                            )
                          ) : (
                            <span className="text-xs text-slate-400 italic">
                              Save to see stock
                            </span>
                          )}
                        </div>
                        {/* Actions */}
                        <div className="col-span-1 flex flex-col items-end gap-1 pt-5">
                          <button
                            type="button"
                            onClick={() =>
                              updateVariant(idx, { _expanded: !v._expanded })
                            }
                            className="text-xs text-indigo-600 hover:text-indigo-500"
                            title="More fields"
                          >
                            {v._expanded ? "−" : "+"}
                          </button>
                          <button
                            type="button"
                            onClick={() => removeVariant(idx)}
                            disabled={
                              draft.variants_draft.filter((x) => !x._destroy)
                                .length <= 1
                            }
                            className="text-xs text-slate-400 hover:text-red-500 disabled:opacity-30 disabled:cursor-not-allowed"
                            title="Remove variant"
                          >
                            ✕
                          </button>
                        </div>
                      </div>

                      {/* Expanded: extra fields */}
                      {v._expanded && (
                        <div className="grid grid-cols-12 gap-2 pt-2 border-t border-slate-100">
                          <div className="col-span-2">
                            <label className="block text-[10px] text-slate-500">
                              Barcode
                            </label>
                            <input
                              value={v.barcode}
                              onChange={(e) =>
                                updateVariant(idx, { barcode: e.target.value })
                              }
                              className="w-full rounded border border-slate-200 px-2 py-1 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-indigo-400"
                            />
                          </div>
                          <div className="col-span-2">
                            <label className="block text-[10px] text-slate-500">
                              Cost per item
                            </label>
                            <input
                              value={v.cost_per_item}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  cost_per_item: e.target.value,
                                })
                              }
                              type="number"
                              step="0.01"
                              min="0"
                              className="w-full rounded border border-slate-200 px-2 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-400"
                            />
                          </div>
                          <div className="col-span-1">
                            <label className="block text-[10px] text-slate-500">
                              Weight
                            </label>
                            <input
                              value={v.weight}
                              onChange={(e) =>
                                updateVariant(idx, { weight: e.target.value })
                              }
                              type="number"
                              step="0.001"
                              min="0"
                              className="w-full rounded border border-slate-200 px-2 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-indigo-400"
                            />
                          </div>
                          <div className="col-span-1">
                            <label className="block text-[10px] text-slate-500">
                              Unit
                            </label>
                            <select
                              value={v.weight_unit}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  weight_unit: e.target
                                    .value as VariantDraft["weight_unit"],
                                })
                              }
                              className="w-full rounded border border-slate-200 px-1 py-1 text-xs focus:outline-none"
                            >
                              <option value="kg">kg</option>
                              <option value="g">g</option>
                              <option value="lb">lb</option>
                              <option value="oz">oz</option>
                            </select>
                          </div>
                          <div className="col-span-2">
                            <label className="block text-[10px] text-slate-500">
                              Inventory policy
                            </label>
                            <select
                              value={v.inventory_policy}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  inventory_policy: e.target
                                    .value as VariantDraft["inventory_policy"],
                                })
                              }
                              className="w-full rounded border border-slate-200 px-1 py-1 text-xs focus:outline-none"
                            >
                              <option value="deny">Deny when 0</option>
                              <option value="continue">Continue selling</option>
                            </select>
                          </div>
                          <div className="col-span-2">
                            <label className="block text-[10px] text-slate-500">
                              HS code
                            </label>
                            <input
                              value={v.hs_code}
                              onChange={(e) =>
                                updateVariant(idx, { hs_code: e.target.value })
                              }
                              className="w-full rounded border border-slate-200 px-2 py-1 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-indigo-400"
                            />
                          </div>
                          <div className="col-span-2">
                            <label className="block text-[10px] text-slate-500">
                              Country of origin
                            </label>
                            <input
                              value={v.country_of_origin}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  country_of_origin: e.target.value,
                                })
                              }
                              placeholder="e.g. US"
                              maxLength={2}
                              className="w-full rounded border border-slate-200 px-2 py-1 text-xs uppercase focus:outline-none focus:ring-1 focus:ring-indigo-400"
                            />
                          </div>
                          <div className="col-span-12 flex items-center gap-4 pt-1">
                            <label className="inline-flex items-center gap-1.5 text-xs text-slate-600">
                              <input
                                type="checkbox"
                                checked={v.requires_shipping}
                                onChange={(e) =>
                                  updateVariant(idx, {
                                    requires_shipping: e.target.checked,
                                  })
                                }
                                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                              />
                              Requires shipping
                            </label>
                            <label className="inline-flex items-center gap-1.5 text-xs text-slate-600">
                              <input
                                type="checkbox"
                                checked={v.taxable}
                                onChange={(e) =>
                                  updateVariant(idx, {
                                    taxable: e.target.checked,
                                  })
                                }
                                className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                              />
                              Charge tax
                            </label>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : (
              <div className="px-4 py-6 text-center text-sm text-slate-400">
                No variants — click "+ Add variant" to add one
              </div>
            )}
          </div>
        </div>

        {/* Right col */}
        <div className="space-y-4">
          {/* Status */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Status
            </h2>
            <select
              value={draft.status}
              onChange={(e) =>
                setDraftField("status", e.target.value as Product["status"])
              }
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <option value="active">Active</option>
              <option value="draft">Draft</option>
              <option value="archived">Archived</option>
            </select>
          </div>

          {/* Organization */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Organization
            </h2>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Vendor
              </label>
              <input
                value={draft.vendor ?? ""}
                onChange={(e) => setDraftField("vendor", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Type
              </label>
              <input
                value={draft.product_type ?? ""}
                onChange={(e) => setDraftField("product_type", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Handle
              </label>
              <input
                value={draft.handle}
                onChange={(e) => setDraftField("handle", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            {/* Tags */}
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                Tags
              </label>
              {draft.tags && draft.tags.length > 0 && (
                <div className="flex flex-wrap gap-1 mb-2">
                  {draft.tags.map((t) => (
                    <span
                      key={t}
                      className="inline-flex items-center gap-1 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                    >
                      {t}
                      <button
                        onClick={() =>
                          setDraftField(
                            "tags",
                            (draft.tags ?? []).filter((x) => x !== t),
                          )
                        }
                        className="text-slate-400 hover:text-red-500 leading-none"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              )}
              <input
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if ((e.key === "Enter" || e.key === ",") && tagInput.trim()) {
                    e.preventDefault();
                    const newTag = tagInput.trim().replace(/,$/, "");
                    if (!draft.tags?.includes(newTag)) {
                      setDraftField("tags", [...(draft.tags ?? []), newTag]);
                    }
                    setTagInput("");
                  }
                }}
                placeholder="Add tag, press Enter"
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
          </div>

          {/* Collections */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Collections
            </h2>
            <AsyncCombobox
              selected={selectedCollections}
              loadOptions={loadCollectionOptions}
              placeholder="Search custom collections..."
              emptyMessage="No custom collections found"
              onChange={(selected) => {
                setSelectedCollections(selected);
                setDraftField(
                  "collection_ids",
                  selected.map((option) => option.value),
                );
              }}
            />
          </div>

          {/* Metafields */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
                Category metafields
              </h2>
              <button
                type="button"
                onClick={addCustomMetafield}
                className="text-xs font-medium text-indigo-600 hover:text-indigo-500"
              >
                + Custom
              </button>
            </div>
            <div className="grid grid-cols-1 gap-2">
              {CATEGORY_METAFIELDS.map((definition) => {
                const value =
                  draft.metafields_draft.find(
                    (row) =>
                      row.namespace === "category" &&
                      row.key === definition.key,
                  )?.value ?? "";
                return (
                  <label key={definition.key} className="block">
                    <span className="mb-1 block text-xs font-medium text-slate-600">
                      {definition.label}
                    </span>
                    <input
                      value={value}
                      onChange={(e) =>
                        setMetafieldValue(
                          "category",
                          definition.key,
                          e.target.value,
                        )
                      }
                      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </label>
                );
              })}
            </div>
            {draft.metafields_draft.filter(
              (row) => row.namespace !== "category",
            ).length > 0 && (
              <div className="border-t border-slate-100 pt-3 space-y-2">
                {draft.metafields_draft
                  .filter((row) => row.namespace !== "category")
                  .map((row, idx) => (
                    <div
                      key={`${row.namespace}-${row.key}-${idx}`}
                      className="grid grid-cols-12 gap-1.5"
                    >
                      <input
                        value={row.namespace}
                        onChange={(e) =>
                          updateCustomMetafield(idx, {
                            namespace: e.target.value,
                          })
                        }
                        placeholder="namespace"
                        className="col-span-3 rounded border border-slate-300 px-2 py-1.5 text-xs"
                      />
                      <input
                        value={row.key}
                        onChange={(e) =>
                          updateCustomMetafield(idx, { key: e.target.value })
                        }
                        placeholder="key"
                        className="col-span-3 rounded border border-slate-300 px-2 py-1.5 text-xs"
                      />
                      <input
                        value={row.value}
                        onChange={(e) =>
                          updateCustomMetafield(idx, { value: e.target.value })
                        }
                        placeholder="value"
                        className="col-span-5 rounded border border-slate-300 px-2 py-1.5 text-xs"
                      />
                      <button
                        type="button"
                        onClick={() => removeCustomMetafield(idx)}
                        className="col-span-1 text-xs text-slate-400 hover:text-red-500"
                      >
                        ×
                      </button>
                    </div>
                  ))}
              </div>
            )}
          </div>

          {/* SEO */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              SEO
            </h2>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                SEO Title
              </label>
              <input
                value={draft.seo_title ?? ""}
                onChange={(e) => setDraftField("seo_title", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-600 mb-1">
                SEO Description
              </label>
              <textarea
                rows={3}
                value={draft.seo_description ?? ""}
                onChange={(e) =>
                  setDraftField("seo_description", e.target.value)
                }
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
          </div>

          {/* Inventory summary */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-1.5 text-xs text-slate-600">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-2">
              Inventory summary
            </h2>
            <div>
              <span className="text-slate-500">Total in stock: </span>
              <span className="font-medium text-slate-900">
                {product.inventory_total ?? 0}
              </span>
            </div>
            <div>
              <span className="text-slate-500">Variants with stock: </span>
              <span className="font-medium text-slate-900">
                {product.variants_in_stock_count ?? 0} /{" "}
                {product.variants_count ?? 0}
              </span>
            </div>
          </div>

          {/* Timestamps */}
          <div className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-1 text-xs text-slate-600">
            <div>
              <span className="text-slate-500">Created:</span>{" "}
              {new Date(product.created_at).toLocaleString()}
            </div>
            <div>
              <span className="text-slate-500">Updated:</span>{" "}
              {new Date(product.updated_at).toLocaleString()}
            </div>
            {product.shopify_product_id && (
              <div>
                <span className="text-slate-500">Shopify ID:</span>{" "}
                {product.shopify_product_id}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
