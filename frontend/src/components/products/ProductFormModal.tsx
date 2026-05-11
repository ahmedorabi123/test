import { useEffect, useState } from "react";
import { productsApi, type Product, type Variant } from "../../api/products";
import { warehousesApi, type Warehouse } from "../../api/inventory";
import { Modal } from "../ui/Modal";

interface StockItemDraft {
  id?: string;
  warehouse_id: string;
  quantity_on_hand: string;
  low_stock_threshold: string;
}

interface ProductImageDraft {
  id?: string;
  src: string;
  alt: string;
  position: number;
  _destroy?: boolean;
}

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
  stock_items: StockItemDraft[];
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
  stock_items: [],
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
  const [images, setImages] = useState<ProductImageDraft[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [tagsInput, setTagsInput] = useState("");
  const [seoTitle, setSeoTitle] = useState("");
  const [seoDescription, setSeoDescription] = useState("");
  const [publishedScope, setPublishedScope] = useState<"web" | "global">("web");
  const [giftCard, setGiftCard] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load existing product when in edit mode
  useEffect(() => {
    warehousesApi
      .list()
      .then((rows) => setWarehouses(rows.filter((w) => w.active)))
      .catch(() => setWarehouses([]));
  }, []);

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
            stock_items: (v.stock_items ?? []).map((stockItem) => ({
              id: stockItem.id,
              warehouse_id: stockItem.warehouse_id,
              quantity_on_hand: String(stockItem.quantity_on_hand ?? 0),
              low_stock_threshold: String(stockItem.low_stock_threshold ?? 0),
            })),
          })),
        );
        setImages(
          (p.images ?? []).map((image, idx) => ({
            id: image.id,
            src: image.src,
            alt: image.alt ?? "",
            position: image.position ?? idx + 1,
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
      {
        ...BLANK_VARIANT,
        title: `Variant ${visibleVariants.length + 1}`,
        stock_items: [],
      },
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

  const updateVariantStock = (
    variantIdx: number,
    warehouseId: string,
    patch: Partial<StockItemDraft>,
  ) => {
    const variant = visibleVariants[variantIdx];
    const stockItems = [...(variant.stock_items ?? [])];
    const stockIdx = stockItems.findIndex(
      (item) => item.warehouse_id === warehouseId,
    );
    if (stockIdx >= 0) {
      stockItems[stockIdx] = { ...stockItems[stockIdx], ...patch };
    } else {
      stockItems.push({
        warehouse_id: warehouseId,
        quantity_on_hand: "0",
        low_stock_threshold: "0",
        ...patch,
      });
    }
    updateVariant(variantIdx, { stock_items: stockItems });
  };

  const stockDraftFor = (variant: VariantDraft, warehouseId: string) =>
    variant.stock_items.find((item) => item.warehouse_id === warehouseId) ?? {
      warehouse_id: warehouseId,
      quantity_on_hand: "0",
      low_stock_threshold: "0",
    };

  const visibleImages = images.filter((image) => !image._destroy);

  const addImage = () =>
    setImages((prev) => [
      ...prev,
      { src: "", alt: "", position: visibleImages.length + 1 },
    ]);

  const updateImage = (idx: number, patch: Partial<ProductImageDraft>) => {
    const visibleIndexes = images.reduce<number[]>((acc, image, imageIdx) => {
      if (!image._destroy) acc.push(imageIdx);
      return acc;
    }, []);
    const imageIdx = visibleIndexes[idx];
    setImages((prev) =>
      prev.map((image, i) => (i === imageIdx ? { ...image, ...patch } : image)),
    );
  };

  const removeImage = (idx: number) => {
    const visibleIndexes = images.reduce<number[]>((acc, image, imageIdx) => {
      if (!image._destroy) acc.push(imageIdx);
      return acc;
    }, []);
    const imageIdx = visibleIndexes[idx];
    const image = images[imageIdx];
    if (image.id) {
      setImages((prev) =>
        prev.map((row, i) =>
          i === imageIdx ? { ...row, _destroy: true } : row,
        ),
      );
    } else {
      setImages((prev) => prev.filter((_, i) => i !== imageIdx));
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
        const stockItemsAttributes = v.stock_items
          .filter(
            (stockItem) =>
              stockItem.id ||
              Number(stockItem.quantity_on_hand || 0) !== 0 ||
              Number(stockItem.low_stock_threshold || 0) !== 0,
          )
          .map((stockItem) => ({
            id: stockItem.id,
            warehouse_id: stockItem.warehouse_id,
            quantity_on_hand: Number(stockItem.quantity_on_hand || 0),
            low_stock_threshold: Number(stockItem.low_stock_threshold || 0),
          }));
        if (stockItemsAttributes.length > 0) {
          base.stock_items_attributes = stockItemsAttributes;
        }
        return base;
      });

      const imageAttrs = images
        .filter((image) => image.id || image.src.trim() || image._destroy)
        .map((image, idx) => ({
          id: image.id,
          src: image.src.trim(),
          alt: image.alt.trim() || null,
          position: idx + 1,
          _destroy: image._destroy,
        }));

      const tags = tagsInput
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean);

      const payload: Partial<Product> & {
        variants_attributes?: unknown[];
        product_images_attributes?: unknown[];
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
        product_images_attributes: imageAttrs,
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
    <Modal open onClose={onClose} size="xl" title={isEdit ? "Edit product" : "New product"}>
        {loadingProduct ? (
          <div className="py-12 text-center text-sm text-gray-400">
            Loading product…
          </div>
        ) : (
          <form onSubmit={submit} className="space-y-5">
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
                className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
              />
            </div>

            {/* Handle + Status */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Handle
                </label>
                <input
                  value={handle}
                  onChange={(e) => setHandle(e.target.value)}
                  placeholder="auto-generated from title"
                  className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 font-mono text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
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
                  className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
                >
                  <option value="draft">Draft</option>
                  <option value="active">Active</option>
                  <option value="archived">Archived</option>
                </select>
              </div>
            </div>

            {/* Vendor + Type */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Vendor
                </label>
                <input
                  value={vendor}
                  onChange={(e) => setVendor(e.target.value)}
                  placeholder="e.g. ACME Apparel"
                  className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
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
                  className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
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
                className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
              />
            </div>

            {/* Published scope + gift card */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Published scope
                </label>
                <select
                  value={publishedScope}
                  onChange={(e) =>
                    setPublishedScope(e.target.value as "web" | "global")
                  }
                  className="min-h-11 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100"
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
                  Images
                </label>
                <button
                  type="button"
                  onClick={addImage}
                  className="text-xs font-medium text-indigo-600 hover:text-indigo-500"
                >
                  + Add image
                </button>
              </div>
              {visibleImages.length > 0 && (
                <div className="space-y-2 rounded-lg border border-gray-200 p-2">
                  {visibleImages.map((image, idx) => (
                    <div
                      key={image.id ?? `image-${idx}`}
                      className="grid grid-cols-1 items-center gap-2 sm:grid-cols-12"
                    >
                      <input
                        value={image.src}
                        onChange={(e) =>
                          updateImage(idx, { src: e.target.value })
                        }
                        placeholder="Image URL"
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-7"
                      />
                      <input
                        value={image.alt}
                        onChange={(e) =>
                          updateImage(idx, { alt: e.target.value })
                        }
                        placeholder="Alt text"
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-4"
                      />
                      <button
                        type="button"
                        onClick={() => removeImage(idx)}
                        className="min-h-10 text-xs text-gray-400 hover:text-red-500 sm:col-span-1"
                        aria-label="Remove image"
                      >
                        Remove
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

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
              <div className="mb-1 hidden grid-cols-12 gap-2 px-1 sm:grid">
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
                    <div className="grid grid-cols-1 items-center gap-2 sm:grid-cols-12">
                      <input
                        value={v.title}
                        onChange={(e) =>
                          updateVariant(idx, { title: e.target.value })
                        }
                        placeholder="e.g. Black / M"
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-4"
                      />
                      <input
                        value={v.sku}
                        onChange={(e) =>
                          updateVariant(idx, { sku: e.target.value })
                        }
                        placeholder="SKU"
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 font-mono text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-3"
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
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-2"
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
                        className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-2"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          updateVariant(idx, { _expanded: !v._expanded })
                        }
                        className="min-h-10 text-xs text-indigo-600 hover:text-indigo-500 sm:col-span-1"
                        aria-label="Toggle more attributes"
                        title="More attributes"
                      >
                        {v._expanded ? "−" : "+"}
                      </button>
                    </div>

                    {v._expanded && (
                      <div className="grid grid-cols-1 gap-2 border-t border-gray-100 pt-1 sm:grid-cols-12">
                        <div className="sm:col-span-3">
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
                        <div className="sm:col-span-2">
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
                        <div className="sm:col-span-2">
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
                        <div className="sm:col-span-1">
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
                        <div className="sm:col-span-2">
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
                        <div className="sm:col-span-2">
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
                        <div className="sm:col-span-3">
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
                        <div className="flex flex-col gap-2 pt-1 sm:col-span-9 sm:flex-row sm:items-center sm:gap-4">
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
                        {warehouses.length > 0 && (
                          <div className="border-t border-gray-100 pt-2 sm:col-span-12">
                            <div className="mb-1 text-[10px] font-medium text-gray-500">
                              Warehouse stock
                            </div>
                            <div className="mb-1 hidden grid-cols-12 gap-2 px-1 sm:grid">
                              <span className="col-span-6 text-[10px] text-gray-400">
                                Warehouse
                              </span>
                              <span className="col-span-3 text-[10px] text-gray-400">
                                On hand
                              </span>
                              <span className="col-span-3 text-[10px] text-gray-400">
                                Low stock
                              </span>
                            </div>
                            <div className="space-y-1">
                              {warehouses.map((warehouse) => {
                                const stockDraft = stockDraftFor(
                                  v,
                                  warehouse.id,
                                );
                                return (
                                  <div
                                    key={warehouse.id}
                                    className="grid grid-cols-1 items-center gap-2 sm:grid-cols-12"
                                  >
                                    <div
                                      className="truncate text-xs text-gray-600 sm:col-span-6"
                                      title={warehouse.name}
                                    >
                                      {warehouse.name}
                                    </div>
                                    <input
                                      type="number"
                                      value={stockDraft.quantity_on_hand}
                                      onChange={(e) =>
                                        updateVariantStock(idx, warehouse.id, {
                                          quantity_on_hand: e.target.value,
                                        })
                                      }
                                      className="min-h-10 rounded-md border border-gray-200 px-2 py-1 text-xs sm:col-span-3"
                                    />
                                    <input
                                      type="number"
                                      min="0"
                                      value={stockDraft.low_stock_threshold}
                                      onChange={(e) =>
                                        updateVariantStock(idx, warehouse.id, {
                                          low_stock_threshold: e.target.value,
                                        })
                                      }
                                      className="min-h-10 rounded-md border border-gray-200 px-2 py-1 text-xs sm:col-span-3"
                                    />
                                  </div>
                                );
                              })}
                            </div>
                          </div>
                        )}
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
            <div className="flex flex-col-reverse gap-2 border-t border-gray-100 pt-4 sm:flex-row sm:items-center sm:justify-end">
              <button
                type="button"
                onClick={onClose}
                className="min-h-11 rounded-lg border border-gray-200 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={submitting}
                className="min-h-11 rounded-lg bg-indigo-600 px-4 text-sm font-medium text-white shadow-sm hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
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
    </Modal>
  );
}
