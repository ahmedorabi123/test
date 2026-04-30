import { useEffect, useState } from "react";
import { productsApi, type Product, type Variant } from "../../api/products";

interface Props {
  /** undefined = create mode; string = edit mode (product id) */
  productId?: string;
  onClose: () => void;
  onSaved: () => void;
}

interface VariantDraft {
  /** Existing variant id — present when editing, absent for new rows */
  id?: string;
  sku: string;
  title: string;
  price: string;
  compare_at_price: string;
  barcode: string;
  cost_per_item: string;
  weight: string;
  weight_unit: "kg" | "g" | "lb" | "oz";
  inventory_policy: "deny" | "continue";
  requires_shipping: boolean;
  taxable: boolean;
  hs_code: string;
  country_of_origin: string;
  /** UI-only: collapse the "more" row */
  _expanded?: boolean;
  /** Rails nested-attributes destroy flag */
  _destroy?: boolean;
}

const BLANK_VARIANT: VariantDraft = {
  sku: "",
  title: "Default",
  price: "0.00",
  compare_at_price: "",
  barcode: "",
  cost_per_item: "",
  weight: "",
  weight_unit: "kg",
  inventory_policy: "deny",
  requires_shipping: true,
  taxable: true,
  hs_code: "",
  country_of_origin: "",
};

function apiError(e: unknown): string {
  const err = e as {
    response?: { data?: { error?: { detail?: string } | string } };
  };
  return (
    (typeof err.response?.data?.error === "object" &&
      err.response?.data?.error?.detail) ||
    (typeof err.response?.data?.error === "string" &&
      err.response?.data?.error) ||
    "Something went wrong"
  );
}

export default function ProductFormModal({
  productId,
  onClose,
  onSaved,
}: Props) {
  const isEdit = productId !== undefined;

  const [loadingProduct, setLoadingProduct] = useState(isEdit);
  const [title, setTitle] = useState("");
  const [handle, setHandle] = useState("");
  const [status, setStatus] = useState<"active" | "draft" | "archived">(
    "draft",
  );
  const [vendor, setVendor] = useState("");
  const [productType, setProductType] = useState("");
  const [description, setDescription] = useState("");
  const [variants, setVariants] = useState<VariantDraft[]>([
    { ...BLANK_VARIANT },
  ]);
  const [tagsInput, setTagsInput] = useState("");
  const [seoTitle, setSeoTitle] = useState("");
  const [seoDescription, setSeoDescription] = useState("");
  const [publishedScope, setPublishedScope] = useState<"web" | "global">("web");
  const [giftCard, setGiftCard] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load existing product when in edit mode
  useEffect(() => {
    if (!productId) return;
    setLoadingProduct(true);
    productsApi
      .get(productId)
      .then((p) => {
        setTitle(p.title);
        setHandle(p.handle);
        setStatus(p.status);
        setVendor(p.vendor ?? "");
        setProductType(p.product_type ?? "");
        setDescription(p.description ?? "");
        setVariants(
          (p.variants ?? []).map((v: Variant) => ({
            id: v.id,
            sku: v.sku ?? "",
            title: v.title,
            price: String(v.price),
            compare_at_price: v.compare_at_price
              ? String(v.compare_at_price)
              : "",
            barcode: v.barcode ?? "",
            cost_per_item: v.cost_per_item ? String(v.cost_per_item) : "",
            weight: v.weight ? String(v.weight) : "",
            weight_unit: (v.weight_unit ?? "kg") as VariantDraft["weight_unit"],
            inventory_policy: (v.inventory_policy ??
              "deny") as VariantDraft["inventory_policy"],
            requires_shipping: v.requires_shipping ?? true,
            taxable: v.taxable ?? true,
            hs_code: v.hs_code ?? "",
            country_of_origin: v.country_of_origin ?? "",
          })),
        );
        setTagsInput((p.tags ?? []).join(", "));
        setSeoTitle(p.seo_title ?? "");
        setSeoDescription(p.seo_description ?? "");
        setPublishedScope((p.published_scope ?? "web") as "web" | "global");
        setGiftCard(Boolean(p.gift_card));
      })
      .catch((e) => setError(apiError(e)))
      .finally(() => setLoadingProduct(false));
  }, [productId]);

  const visibleVariants = variants.filter((v) => !v._destroy);

  const updateVariant = (idx: number, patch: Partial<VariantDraft>) => {
    // idx is index within visibleVariants — map back to full array
    const visIdx = variants.reduce<number[]>((acc, v, i) => {
      if (!v._destroy) acc.push(i);
      return acc;
    }, [])[idx];
    setVariants((prev) =>
      prev.map((v, i) => (i === visIdx ? { ...v, ...patch } : v)),
    );
  };

  const addVariant = () =>
    setVariants((prev) => [
      ...prev,
      { ...BLANK_VARIANT, title: `Variant ${visibleVariants.length + 1}` },
    ]);

  const removeVariant = (idx: number) => {
    const visIdx = variants.reduce<number[]>((acc, v, i) => {
      if (!v._destroy) acc.push(i);
      return acc;
    }, [])[idx];
    const v = variants[visIdx];
    if (v.id) {
      // existing — mark for Rails to destroy
      setVariants((prev) =>
        prev.map((x, i) => (i === visIdx ? { ...x, _destroy: true } : x)),
      );
    } else {
      // new row — just splice
      setVariants((prev) => prev.filter((_, i) => i !== visIdx));
    }
  };

  const validate = (): string | null => {
    if (!title.trim()) return "Title is required";
    if (visibleVariants.length === 0) return "At least one variant is required";
    for (const v of visibleVariants) {
      if (!v.title.trim()) return "Each variant needs a title";
      if (v.price === "" || Number(v.price) < 0)
        return "Each variant needs a non-negative price";
    }
    return null;
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const validationErr = validate();
    if (validationErr) {
      setError(validationErr);
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      const variantsAttrs = variants.map((v, idx) => {
        const base: Record<string, unknown> = {
          sku: v.sku.trim() || null,
          title: v.title.trim(),
          price: v.price,
          compare_at_price: v.compare_at_price.trim() || null,
          barcode: v.barcode.trim() || null,
          cost_per_item: v.cost_per_item.trim() || null,
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
      });

      const tags = tagsInput
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean);

      const payload: Partial<Product> & {
        variants_attributes?: unknown[];
        tags?: string[];
      } = {
        title: title.trim(),
        handle: handle.trim() || undefined,
        status,
        vendor: vendor.trim() || null,
        product_type: productType.trim() || null,
        description: description.trim() || null,
        tags,
        seo_title: seoTitle.trim() || null,
        seo_description: seoDescription.trim() || null,
        published_scope: publishedScope,
        gift_card: giftCard,
        variants_attributes: variantsAttrs,
      };

      if (isEdit) {
        await productsApi.update(
          productId,
          payload as Parameters<typeof productsApi.update>[1],
        );
      } else {
        await productsApi.create(
          payload as Parameters<typeof productsApi.create>[0],
        );
      }
      onSaved();
    } catch (e) {
      setError(apiError(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-gray-900/50 p-4 sm:p-8"
      onClick={onClose}
    >
      <div
        className="w-full max-w-3xl rounded-xl bg-white shadow-2xl my-4"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <h2 className="text-lg font-semibold text-gray-900">
            {isEdit ? "Edit product" : "New product"}
          </h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
            aria-label="Close"
          >
            <svg className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path
                fillRule="evenodd"
                d="M4.3 4.3a1 1 0 011.4 0L10 8.6l4.3-4.3a1 1 0 111.4 1.4L11.4 10l4.3 4.3a1 1 0 01-1.4 1.4L10 11.4l-4.3 4.3a1 1 0 01-1.4-1.4L8.6 10 4.3 5.7a1 1 0 010-1.4z"
                clipRule="evenodd"
              />
            </svg>
          </button>
        </div>

        {loadingProduct ? (
          <div className="px-6 py-12 text-center text-gray-400 text-sm">
            Loading product…
          </div>
        ) : (
          <form onSubmit={submit} className="px-6 py-4 space-y-5">
            {error && (
              <div className="rounded-md bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700">
                {error}
              </div>
            )}

            {/* Title */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Title <span className="text-red-500">*</span>
              </label>
              <input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="e.g. Classic Tee"
                required
                className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
              />
            </div>

            {/* Handle + Status */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Handle
                </label>
                <input
                  value={handle}
                  onChange={(e) => setHandle(e.target.value)}
                  placeholder="auto-generated from title"
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-mono focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Status
                </label>
                <select
                  value={status}
                  onChange={(e) =>
                    setStatus(e.target.value as "active" | "draft" | "archived")
                  }
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
                >
                  <option value="draft">Draft</option>
                  <option value="active">Active</option>
                  <option value="archived">Archived</option>
                </select>
              </div>
            </div>

            {/* Vendor + Type */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Vendor
                </label>
                <input
                  value={vendor}
                  onChange={(e) => setVendor(e.target.value)}
                  placeholder="e.g. ACME Apparel"
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Product type
                </label>
                <input
                  value={productType}
                  onChange={(e) => setProductType(e.target.value)}
                  placeholder="e.g. T-Shirts"
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
                />
              </div>
            </div>

            {/* Description */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Description
              </label>
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={3}
                placeholder="Short description (HTML allowed)"
                className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none resize-none"
              />
            </div>

            {/* Tags */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Tags
              </label>
              <input
                value={tagsInput}
                onChange={(e) => setTagsInput(e.target.value)}
                placeholder="comma-separated, e.g. summer, sale, new"
                className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
              />
            </div>

            {/* Published scope + gift card */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Published scope
                </label>
                <select
                  value={publishedScope}
                  onChange={(e) =>
                    setPublishedScope(e.target.value as "web" | "global")
                  }
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
                >
                  <option value="web">Online store (web)</option>
                  <option value="global">All channels (global)</option>
                </select>
              </div>
              <div className="flex items-end">
                <label className="inline-flex items-center gap-2 text-sm text-gray-700">
                  <input
                    type="checkbox"
                    checked={giftCard}
                    onChange={(e) => setGiftCard(e.target.checked)}
                    className="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                  />
                  This is a gift card
                </label>
              </div>
            </div>

            {/* SEO panel */}
            <details className="rounded-lg border border-gray-200">
              <summary className="cursor-pointer px-3 py-2 text-sm font-medium text-gray-700">
                Search engine listing (SEO)
              </summary>
              <div className="px-3 pb-3 space-y-3">
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">
                    Page title
                  </label>
                  <input
                    value={seoTitle}
                    onChange={(e) => setSeoTitle(e.target.value)}
                    maxLength={70}
                    className="w-full rounded-md border border-gray-200 px-2 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100"
                  />
                  <div className="text-[10px] text-gray-400 mt-1">
                    {seoTitle.length}/70
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">
                    Meta description
                  </label>
                  <textarea
                    value={seoDescription}
                    onChange={(e) => setSeoDescription(e.target.value)}
                    rows={2}
                    maxLength={320}
                    className="w-full rounded-md border border-gray-200 px-2 py-1.5 text-sm outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 resize-none"
                  />
                  <div className="text-[10px] text-gray-400 mt-1">
                    {seoDescription.length}/320
                  </div>
                </div>
              </div>
            </details>

            {/* Variants */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="block text-sm font-medium text-gray-700">
                  Variants <span className="text-red-500">*</span>
                </label>
                <button
                  type="button"
                  onClick={addVariant}
                  className="text-xs font-medium text-indigo-600 hover:text-indigo-500"
                >
                  + Add variant
                </button>
              </div>

              {/* Column headers */}
              <div className="grid grid-cols-12 gap-2 px-1 mb-1">
                <span className="col-span-4 text-xs text-gray-400">Title</span>
                <span className="col-span-3 text-xs text-gray-400">SKU</span>
                <span className="col-span-2 text-xs text-gray-400">Price</span>
                <span className="col-span-2 text-xs text-gray-400">
                  Compare
                </span>
              </div>

              <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
                {visibleVariants.map((v, idx) => (
                  <div
                    key={v.id ?? `new-${idx}`}
                    className="rounded-lg border border-gray-200 p-2 space-y-2"
                  >
                    <div className="grid grid-cols-12 gap-2 items-center">
                      <input
                        value={v.title}
                        onChange={(e) =>
                          updateVariant(idx, { title: e.target.value })
                        }
                        placeholder="e.g. Black / M"
                        className="col-span-4 rounded-md border border-gray-200 px-2 py-1.5 text-xs focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 outline-none"
                      />
                      <input
                        value={v.sku}
                        onChange={(e) =>
                          updateVariant(idx, { sku: e.target.value })
                        }
                        placeholder="SKU"
                        className="col-span-3 rounded-md border border-gray-200 px-2 py-1.5 text-xs font-mono focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 outline-none"
                      />
                      <input
                        value={v.price}
                        onChange={(e) =>
                          updateVariant(idx, { price: e.target.value })
                        }
                        placeholder="0.00"
                        type="number"
                        step="0.01"
                        min="0"
                        className="col-span-2 rounded-md border border-gray-200 px-2 py-1.5 text-xs focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 outline-none"
                      />
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
                        className="col-span-2 rounded-md border border-gray-200 px-2 py-1.5 text-xs focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 outline-none"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          updateVariant(idx, { _expanded: !v._expanded })
                        }
                        className="col-span-1 text-xs text-indigo-600 hover:text-indigo-500"
                        aria-label="Toggle more attributes"
                        title="More attributes"
                      >
                        {v._expanded ? "−" : "+"}
                      </button>
                    </div>

                    {v._expanded && (
                      <div className="grid grid-cols-12 gap-2 pt-1 border-t border-gray-100">
                        <div className="col-span-3">
                          <label className="block text-[10px] text-gray-500">
                            Barcode
                          </label>
                          <input
                            value={v.barcode}
                            onChange={(e) =>
                              updateVariant(idx, { barcode: e.target.value })
                            }
                            className="w-full rounded-md border border-gray-200 px-2 py-1 text-xs font-mono"
                          />
                        </div>
                        <div className="col-span-2">
                          <label className="block text-[10px] text-gray-500">
                            Cost
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
                            className="w-full rounded-md border border-gray-200 px-2 py-1 text-xs"
                          />
                        </div>
                        <div className="col-span-2">
                          <label className="block text-[10px] text-gray-500">
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
                            className="w-full rounded-md border border-gray-200 px-2 py-1 text-xs"
                          />
                        </div>
                        <div className="col-span-1">
                          <label className="block text-[10px] text-gray-500">
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
                            className="w-full rounded-md border border-gray-200 px-1 py-1 text-xs"
                          >
                            <option value="kg">kg</option>
                            <option value="g">g</option>
                            <option value="lb">lb</option>
                            <option value="oz">oz</option>
                          </select>
                        </div>
                        <div className="col-span-2">
                          <label className="block text-[10px] text-gray-500">
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
                            className="w-full rounded-md border border-gray-200 px-1 py-1 text-xs"
                          >
                            <option value="deny">Deny when 0</option>
                            <option value="continue">Continue selling</option>
                          </select>
                        </div>
                        <div className="col-span-2">
                          <label className="block text-[10px] text-gray-500">
                            HS code
                          </label>
                          <input
                            value={v.hs_code}
                            onChange={(e) =>
                              updateVariant(idx, { hs_code: e.target.value })
                            }
                            className="w-full rounded-md border border-gray-200 px-2 py-1 text-xs font-mono"
                          />
                        </div>
                        <div className="col-span-3">
                          <label className="block text-[10px] text-gray-500">
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
                            className="w-full rounded-md border border-gray-200 px-2 py-1 text-xs uppercase"
                          />
                        </div>
                        <div className="col-span-9 flex items-center gap-4 pt-1">
                          <label className="inline-flex items-center gap-1 text-xs text-gray-600">
                            <input
                              type="checkbox"
                              checked={v.requires_shipping}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  requires_shipping: e.target.checked,
                                })
                              }
                              className="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            />
                            Requires shipping
                          </label>
                          <label className="inline-flex items-center gap-1 text-xs text-gray-600">
                            <input
                              type="checkbox"
                              checked={v.taxable}
                              onChange={(e) =>
                                updateVariant(idx, {
                                  taxable: e.target.checked,
                                })
                              }
                              className="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            />
                            Charge tax
                          </label>
                        </div>
                      </div>
                    )}

                    <div className="flex justify-end">
                      <button
                        type="button"
                        onClick={() => removeVariant(idx)}
                        disabled={visibleVariants.length === 1}
                        className="text-xs text-gray-400 hover:text-red-500 disabled:opacity-30 disabled:cursor-not-allowed"
                        aria-label="Remove variant"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Footer */}
            <div className="flex items-center justify-end gap-2 border-t border-gray-100 pt-4 -mx-6 px-6 -mb-4 pb-4">
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-gray-200 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={submitting}
                className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {submitting
                  ? isEdit
                    ? "Saving…"
                    : "Creating…"
                  : isEdit
                    ? "Save changes"
                    : "Create product"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
