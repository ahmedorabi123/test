import { useCallback, useMemo, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { productsApi, type ProductMetafield } from "../api/products";
import { collectionsApi } from "../api/collections";
import AsyncCombobox, {
  type AsyncComboboxOption,
} from "../components/AsyncCombobox";
import { htmlToText } from "../lib/htmlText";

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

const ALLOWED_MEDIA_TYPES = [
  "image/png",
  "image/jpeg",
  "image/jpg",
  "image/webp",
  "image/gif",
];
const MAX_MEDIA_BYTES = 5 * 1024 * 1024;

type VariantDraft = {
  key: string;
  title: string;
  option1: string;
  option2: string;
  option3: string;
  sku: string;
  price: string;
  compare_at_price: string;
  cost_per_item: string;
  barcode: string;
};

type Draft = {
  title: string;
  handle: string;
  description: string;
  status: "active" | "draft" | "archived";
  vendor: string;
  product_type: string;
  tags: string[];
  seo_title: string;
  seo_description: string;
  metafields: ProductMetafield[];
  collection_ids: string[];
};

const initialDraft: Draft = {
  title: "",
  handle: "",
  description: "",
  status: "active",
  vendor: "",
  product_type: "",
  tags: [],
  seo_title: "",
  seo_description: "",
  metafields: [],
  collection_ids: [],
};

function slugify(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function newVariant(title = "Default"): VariantDraft {
  return {
    key: `variant-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    title,
    option1: "",
    option2: "",
    option3: "",
    sku: "",
    price: "0.00",
    compare_at_price: "",
    cost_per_item: "",
    barcode: "",
  };
}

function uniqueValues(values: string[]) {
  return Array.from(
    new Set(values.map((value) => value.trim()).filter(Boolean)),
  );
}

function buildProductOptions(variants: VariantDraft[]) {
  const definitions = [
    { name: "Option 1", values: uniqueValues(variants.map((v) => v.option1)) },
    { name: "Option 2", values: uniqueValues(variants.map((v) => v.option2)) },
    { name: "Option 3", values: uniqueValues(variants.map((v) => v.option3)) },
  ].filter((definition) => definition.values.length > 0);

  return definitions.map((definition, index) => ({
    name: definition.name,
    position: index + 1,
    product_option_values_attributes: definition.values.map(
      (value, valueIndex) => ({ value, position: valueIndex + 1 }),
    ),
  }));
}

function validateMedia(files: File[]) {
  const invalid = files.find(
    (file) =>
      !ALLOWED_MEDIA_TYPES.includes(file.type) || file.size > MAX_MEDIA_BYTES,
  );
  if (!invalid) return null;

  return invalid.size > MAX_MEDIA_BYTES
    ? `${invalid.name} exceeds 5 MB`
    : `${invalid.name}: unsupported type ${invalid.type || "unknown"}`;
}

export default function NewProductPage() {
  const navigate = useNavigate();
  const mediaInputRef = useRef<HTMLInputElement>(null);
  const [draft, setDraft] = useState<Draft>(initialDraft);
  const [tagInput, setTagInput] = useState("");
  const [variants, setVariants] = useState<VariantDraft[]>([
    newVariant("Default"),
  ]);
  const [selectedCollections, setSelectedCollections] = useState<
    AsyncComboboxOption[]
  >([]);
  const [mediaFiles, setMediaFiles] = useState<File[]>([]);
  const [dragOver, setDragOver] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  const resolvedHandle = useMemo(
    () => draft.handle.trim() || slugify(draft.title),
    [draft.handle, draft.title],
  );

  const setField = <K extends keyof Draft>(field: K, value: Draft[K]) => {
    setDraft((prev) => ({ ...prev, [field]: value }));
  };

  const setCategoryMetafield = (key: string, value: string) => {
    setDraft((prev) => {
      const next = [...prev.metafields];
      const idx = next.findIndex(
        (row) => row.namespace === "category" && row.key === key,
      );
      const row = {
        namespace: "category",
        key,
        type: "single_line_text_field",
        value,
      };
      if (idx >= 0) next[idx] = row;
      else next.push(row);
      return { ...prev, metafields: next };
    });
  };

  const addTag = () => {
    const value = tagInput.trim().replace(/,$/, "");
    if (!value || draft.tags.includes(value)) return;
    setField("tags", [...draft.tags, value]);
    setTagInput("");
  };

  const updateVariant = (index: number, patch: Partial<VariantDraft>) => {
    setVariants((prev) =>
      prev.map((variant, i) =>
        i === index ? { ...variant, ...patch } : variant,
      ),
    );
  };

  const addVariant = () => {
    setVariants((prev) => [...prev, newVariant(`Variant ${prev.length + 1}`)]);
  };

  const removeVariant = (index: number) => {
    setVariants((prev) =>
      prev.length <= 1 ? prev : prev.filter((_, i) => i !== index),
    );
  };

  const appendMedia = (files: File[]) => {
    const validationError = validateMedia(files);
    if (validationError) {
      setError(validationError);
      return;
    }
    setError(null);
    setMediaFiles((prev) => [...prev, ...files]);
  };

  const save = async () => {
    if (!draft.title.trim()) {
      setError("Product title is required");
      return;
    }
    const validVariants = variants.length > 0 ? variants : [newVariant()];
    setSaving(true);
    setError(null);
    try {
      const product = await productsApi.create({
        title: draft.title.trim(),
        handle: resolvedHandle,
        description: htmlToText(draft.description),
        status: draft.status,
        vendor: draft.vendor.trim() || null,
        product_type: draft.product_type.trim() || null,
        tags: draft.tags,
        collection_ids: draft.collection_ids,
        seo_title: draft.seo_title.trim() || null,
        seo_description: draft.seo_description.trim() || null,
        metafields: draft.metafields.filter(
          (row) => row.namespace && row.key && row.value.trim(),
        ),
        product_options_attributes: buildProductOptions(validVariants) as never,
        variants_attributes: validVariants.map((variant, index) => ({
          title: variant.title.trim() || "Default",
          sku: variant.sku.trim() || null,
          price: variant.price || "0.00",
          compare_at_price: variant.compare_at_price.trim() || null,
          cost: variant.cost_per_item.trim() || null,
          cost_per_item: variant.cost_per_item.trim() || null,
          barcode: variant.barcode.trim() || null,
          option1: variant.option1.trim() || null,
          option2: variant.option2.trim() || null,
          option3: variant.option3.trim() || null,
          position: index + 1,
          inventory_policy: "deny",
          inventory_management: "shopify",
          requires_shipping: true,
          taxable: true,
        })),
      });

      if (mediaFiles.length > 0) {
        await productsApi.uploadImages(product.id, mediaFiles);
      }

      navigate(`/products/${product.id}`);
    } catch (e) {
      const err = e as {
        response?: { data?: { error?: { detail?: string } } };
        message?: string;
      };
      setError(
        err.response?.data?.error?.detail ||
          err.message ||
          "Failed to create product",
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="max-w-7xl mx-auto pb-24">
      <div className="sticky top-0 z-30 bg-white/95 backdrop-blur border-b border-slate-200 px-1 py-3 mb-6 flex items-center gap-3">
        <div className="flex-1">
          <Link
            to="/products"
            className="text-sm text-slate-500 hover:text-slate-700"
          >
            Back to Products
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900">New product</h1>
        </div>
        <button
          type="button"
          onClick={() => navigate("/products")}
          className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={save}
          disabled={saving}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
        >
          {saving ? "Creating..." : "Create product"}
        </button>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-5 space-y-4">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Title & description
            </h2>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Title
              </span>
              <input
                autoFocus
                value={draft.title}
                onChange={(e) => setField("title", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Description
              </span>
              <textarea
                rows={7}
                value={draft.description}
                onChange={(e) => setField("description", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </label>
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-5 space-y-4">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
                Variants
              </h2>
              <button
                type="button"
                onClick={addVariant}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
              >
                Add variant
              </button>
            </div>

            <div className="overflow-x-auto rounded-lg border border-slate-200">
              <table className="min-w-[1080px] text-sm">
                <thead className="bg-slate-50 text-xs uppercase text-slate-500">
                  <tr>
                    <th className="px-3 py-2 text-left">Variant</th>
                    <th className="px-3 py-2 text-left">Option 1</th>
                    <th className="px-3 py-2 text-left">Option 2</th>
                    <th className="px-3 py-2 text-left">Option 3</th>
                    <th className="px-3 py-2 text-left">SKU</th>
                    <th className="px-3 py-2 text-right">Price</th>
                    <th className="px-3 py-2 text-right">Compare</th>
                    <th className="px-3 py-2 text-right">Cost</th>
                    <th className="px-3 py-2 text-left">Barcode</th>
                    <th className="px-3 py-2"></th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {variants.map((variant, index) => (
                    <tr key={variant.key}>
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} title`}
                          value={variant.title}
                          onChange={(e) =>
                            updateVariant(index, { title: e.target.value })
                          }
                          className="w-44 rounded border border-slate-300 px-2 py-1"
                        />
                      </td>
                      {(["option1", "option2", "option3"] as const).map(
                        (field, optionIndex) => (
                          <td key={field} className="px-3 py-2">
                            <input
                              aria-label={`Variant ${index + 1} option ${optionIndex + 1}`}
                              value={variant[field]}
                              onChange={(e) =>
                                updateVariant(index, {
                                  [field]: e.target.value,
                                })
                              }
                              className="w-32 rounded border border-slate-300 px-2 py-1"
                            />
                          </td>
                        ),
                      )}
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} SKU`}
                          value={variant.sku}
                          onChange={(e) =>
                            updateVariant(index, { sku: e.target.value })
                          }
                          className="w-36 rounded border border-slate-300 px-2 py-1 font-mono"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} price`}
                          type="number"
                          min={0}
                          step="0.01"
                          value={variant.price}
                          onChange={(e) =>
                            updateVariant(index, { price: e.target.value })
                          }
                          className="w-24 rounded border border-slate-300 px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} compare at price`}
                          type="number"
                          min={0}
                          step="0.01"
                          value={variant.compare_at_price}
                          onChange={(e) =>
                            updateVariant(index, {
                              compare_at_price: e.target.value,
                            })
                          }
                          className="w-24 rounded border border-slate-300 px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} cost`}
                          type="number"
                          min={0}
                          step="0.01"
                          value={variant.cost_per_item}
                          onChange={(e) =>
                            updateVariant(index, {
                              cost_per_item: e.target.value,
                            })
                          }
                          className="w-24 rounded border border-slate-300 px-2 py-1 text-right"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          aria-label={`Variant ${index + 1} barcode`}
                          value={variant.barcode}
                          onChange={(e) =>
                            updateVariant(index, { barcode: e.target.value })
                          }
                          className="w-32 rounded border border-slate-300 px-2 py-1 font-mono"
                        />
                      </td>
                      <td className="px-3 py-2 text-right">
                        <button
                          type="button"
                          onClick={() => removeVariant(index)}
                          disabled={variants.length <= 1}
                          className="text-xs font-medium text-rose-600 hover:text-rose-700 disabled:text-slate-300"
                        >
                          Remove
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-5 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Media
            </h2>
            <div
              onClick={() => mediaInputRef.current?.click()}
              onDragOver={(event) => {
                event.preventDefault();
                setDragOver(true);
              }}
              onDragLeave={() => setDragOver(false)}
              onDrop={(event) => {
                event.preventDefault();
                setDragOver(false);
                appendMedia(Array.from(event.dataTransfer.files));
              }}
              className={`flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed px-4 py-6 text-sm transition ${
                dragOver
                  ? "border-indigo-400 bg-indigo-50"
                  : "border-slate-300 bg-slate-50 hover:bg-slate-100"
              }`}
            >
              <span className="font-medium text-slate-700">
                Drag files here or click to upload
              </span>
              <span className="text-xs text-slate-400">
                PNG, JPEG, WEBP, GIF · up to 5 MB each
              </span>
              <input
                ref={mediaInputRef}
                aria-label="Upload product media"
                type="file"
                multiple
                accept={ALLOWED_MEDIA_TYPES.join(",")}
                className="sr-only"
                onChange={(event) => {
                  appendMedia(Array.from(event.target.files ?? []));
                  event.target.value = "";
                }}
              />
            </div>
            {mediaFiles.length > 0 && (
              <div className="divide-y divide-slate-100 rounded-lg border border-slate-200">
                {mediaFiles.map((file, index) => (
                  <div
                    key={`${file.name}-${file.size}-${index}`}
                    className="flex items-center justify-between gap-3 px-3 py-2 text-sm"
                  >
                    <span className="truncate text-slate-700">
                      {file.name}
                    </span>
                    <button
                      type="button"
                      onClick={() =>
                        setMediaFiles((prev) =>
                          prev.filter((_, fileIndex) => fileIndex !== index),
                        )
                      }
                      className="text-xs font-medium text-rose-600 hover:text-rose-700"
                    >
                      Remove
                    </button>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>

        <div className="space-y-4">
          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Status
            </h2>
            <select
              value={draft.status}
              onChange={(e) =>
                setField("status", e.target.value as Draft["status"])
              }
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="active">Active</option>
              <option value="draft">Draft</option>
              <option value="archived">Archived</option>
            </select>
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Organization
            </h2>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Vendor
              </span>
              <input
                value={draft.vendor}
                onChange={(e) => setField("vendor", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Type
              </span>
              <input
                value={draft.product_type}
                onChange={(e) => setField("product_type", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Handle
              </span>
              <input
                value={draft.handle}
                placeholder={resolvedHandle}
                onChange={(e) => setField("handle", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm font-mono"
              />
            </label>
            <div>
              <span className="mb-1 block text-xs font-medium text-slate-600">
                Tags
              </span>
              {draft.tags.length > 0 && (
                <div className="mb-2 flex flex-wrap gap-1">
                  {draft.tags.map((tag) => (
                    <span
                      key={tag}
                      className="inline-flex items-center gap-1 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() =>
                          setField(
                            "tags",
                            draft.tags.filter((x) => x !== tag),
                          )
                        }
                        className="text-slate-400 hover:text-red-500"
                      >
                        x
                      </button>
                    </span>
                  ))}
                </div>
              )}
              <input
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === ",") {
                    e.preventDefault();
                    addTag();
                  }
                }}
                placeholder="Add tag, press Enter"
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </div>
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
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
                setField(
                  "collection_ids",
                  selected.map((option) => option.value),
                );
              }}
            />
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Category metafields
            </h2>
            {CATEGORY_METAFIELDS.map((definition) => {
              const value =
                draft.metafields.find(
                  (row) =>
                    row.namespace === "category" && row.key === definition.key,
                )?.value ?? "";
              return (
                <label key={definition.key} className="block">
                  <span className="mb-1 block text-xs font-medium text-slate-600">
                    {definition.label}
                  </span>
                  <input
                    value={value}
                    onChange={(e) =>
                      setCategoryMetafield(definition.key, e.target.value)
                    }
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
                  />
                </label>
              );
            })}
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-4 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              SEO
            </h2>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                SEO title
              </span>
              <input
                value={draft.seo_title}
                onChange={(e) => setField("seo_title", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-medium text-slate-600">
                SEO description
              </span>
              <textarea
                rows={3}
                value={draft.seo_description}
                onChange={(e) => setField("seo_description", e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              />
            </label>
          </section>
        </div>
      </div>
    </div>
  );
}
