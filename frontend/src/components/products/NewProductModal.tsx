import { useState } from "react";
import { productsApi, type Product, type Variant } from "../../api/products";
import { Modal } from "../ui/Modal";

interface Props {
  onClose: () => void;
  onCreated: (product: Product) => void;
}

interface VariantDraft {
  sku: string;
  title: string;
  price: string;
  compare_at_price: string;
}

const BLANK_VARIANT: VariantDraft = {
  sku: "",
  title: "Default",
  price: "0.00",
  compare_at_price: "",
};

export default function NewProductModal({ onClose, onCreated }: Props) {
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
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const updateVariant = (idx: number, patch: Partial<VariantDraft>) => {
    setVariants((prev) =>
      prev.map((v, i) => (i === idx ? { ...v, ...patch } : v)),
    );
  };

  const addVariant = () =>
    setVariants((prev) => [
      ...prev,
      { ...BLANK_VARIANT, title: `Variant ${prev.length + 1}` },
    ]);

  const removeVariant = (idx: number) =>
    setVariants((prev) => prev.filter((_, i) => i !== idx));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!title.trim()) {
      setError("Title is required");
      return;
    }
    if (variants.length === 0) {
      setError("At least one variant is required");
      return;
    }
    for (const v of variants) {
      if (!v.title.trim()) {
        setError("Each variant needs a title");
        return;
      }
      if (v.price === "" || Number(v.price) < 0) {
        setError("Each variant needs a non-negative price");
        return;
      }
    }

    setSubmitting(true);
    try {
      const payload: Partial<Product> & {
        variants_attributes?: Partial<Variant>[];
      } = {
        title: title.trim(),
        handle: handle.trim() || undefined,
        status,
        vendor: vendor.trim() || null,
        product_type: productType.trim() || null,
        description: description.trim() || null,
        variants_attributes: variants.map((v, idx) => ({
          sku: v.sku.trim() || null,
          title: v.title.trim(),
          price: v.price,
          compare_at_price: v.compare_at_price.trim() || null,
          position: idx + 1,
        })),
      };
      const created = await productsApi.create(payload);
      onCreated(created);
    } catch (e: unknown) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } | string } };
      };
      const detail =
        (typeof err.response?.data?.error === "object" &&
          err.response?.data?.error?.detail) ||
        (typeof err.response?.data?.error === "string" &&
          err.response?.data?.error) ||
        "Failed to create product";
      setError(String(detail));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Modal open onClose={onClose} size="xl" title="New product">
        <form onSubmit={submit} className="space-y-5">
          {error && (
            <div className="rounded-md bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700">
              {error}
            </div>
          )}

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

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Description
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={3}
              placeholder="Short description (HTML allowed)"
              className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none"
            />
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

            <div className="space-y-2">
              {variants.map((v, idx) => (
                <div
                  key={idx}
                  className="grid grid-cols-1 items-start gap-2 rounded-lg border border-gray-200 p-2 sm:grid-cols-12"
                >
                  <input
                    value={v.title}
                    onChange={(e) =>
                      updateVariant(idx, { title: e.target.value })
                    }
                    placeholder="Title (e.g. Black / M)"
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
                    placeholder="Price"
                    type="number"
                    step="0.01"
                    min="0"
                    className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-2"
                  />
                  <input
                    value={v.compare_at_price}
                    onChange={(e) =>
                      updateVariant(idx, { compare_at_price: e.target.value })
                    }
                    placeholder="Compare"
                    type="number"
                    step="0.01"
                    min="0"
                    className="min-h-10 rounded-md border border-gray-200 px-2 py-1.5 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-100 sm:col-span-2"
                  />
                  <button
                    type="button"
                    onClick={() => removeVariant(idx)}
                    disabled={variants.length === 1}
                    className="min-h-10 text-xs text-red-500 hover:text-red-700 disabled:cursor-not-allowed disabled:text-gray-300 sm:col-span-1"
                    aria-label="Remove variant"
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          </div>

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
              {submitting ? "Creating…" : "Create product"}
            </button>
          </div>
        </form>
    </Modal>
  );
}
