import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { productsApi, type ProductMetafield } from "../api/products";
import { collectionsApi } from "../api/collections";
import { warehousesApi, type Warehouse } from "../api/inventory";
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

type OptionDraft = { name: string; values: string };
type VariantDraft = {
  key: string;
  title: string;
  option1?: string;
  option2?: string;
  option3?: string;
  sku: string;
  price: string;
  compare_at_price: string;
  cost_per_item: string;
  barcode: string;
  stock: Record<string, string>;
  threshold: Record<string, string>;
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
  imageUrls: string[];
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
  imageUrls: [""],
};

function slugify(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function parseValues(value: string) {
  return value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function combinations(groups: string[][]) {
  return groups.reduce<string[][]>(
    (acc, group) =>
      acc.flatMap((prefix) => group.map((value) => [...prefix, value])),
    [[]],
  );
}

function buildDefaultVariant(warehouses: Warehouse[]): VariantDraft {
  return {
    key: "default",
    title: "Default",
    sku: "",
    price: "0.00",
    compare_at_price: "",
    cost_per_item: "",
    barcode: "",
    stock: Object.fromEntries(
      warehouses.map((warehouse) => [warehouse.id, "0"]),
    ),
    threshold: Object.fromEntries(
      warehouses.map((warehouse) => [warehouse.id, "0"]),
    ),
  };
}

export default function NewProductPage() {
  const navigate = useNavigate();
  const [draft, setDraft] = useState<Draft>(initialDraft);
  const [tagInput, setTagInput] = useState("");
  const [options, setOptions] = useState<OptionDraft[]>([
    { name: "Color", values: "" },
    { name: "Size", values: "" },
  ]);
  const [variants, setVariants] = useState<VariantDraft[]>([]);
  const [selectedCollections, setSelectedCollections] = useState<
    AsyncComboboxOption[]
  >([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    warehousesApi
      .list()
      .then((warehouseRows) => {
        setWarehouses(warehouseRows.filter((warehouse) => warehouse.active));
        setVariants((prev) =>
          prev.length > 0
            ? prev
            : [
                buildDefaultVariant(
                  warehouseRows.filter((warehouse) => warehouse.active),
                ),
              ],
        );
      })
      .catch(() => undefined);
  }, []);

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

  const generateVariants = () => {
    const activeOptions = options
      .map((option) => ({
        name: option.name.trim(),
        values: parseValues(option.values),
      }))
      .filter((option) => option.name && option.values.length > 0)
      .slice(0, 3);
    if (activeOptions.length === 0) {
      setVariants([buildDefaultVariant(warehouses)]);
      return;
    }
    const existingByTitle = new Map(
      variants.map((variant) => [variant.title, variant]),
    );
    setVariants(
      combinations(activeOptions.map((option) => option.values)).map(
        (values, index) => {
          const title = values.join(" / ");
          const existing = existingByTitle.get(title);
          return (
            existing || {
              ...buildDefaultVariant(warehouses),
              key: `${title}-${index}`,
              title,
              option1: values[0],
              option2: values[1],
              option3: values[2],
            }
          );
        },
      ),
    );
  };

  const updateVariant = (index: number, patch: Partial<VariantDraft>) => {
    setVariants((prev) =>
      prev.map((variant, i) =>
        i === index ? { ...variant, ...patch } : variant,
      ),
    );
  };

  const updateVariantStock = (
    index: number,
    warehouseId: string,
    value: string,
  ) => {
    setVariants((prev) =>
      prev.map((variant, i) =>
        i === index
          ? { ...variant, stock: { ...variant.stock, [warehouseId]: value } }
          : variant,
      ),
    );
  };

  const save = async () => {
    if (!draft.title.trim()) {
      setError("Product title is required");
      return;
    }
    const validVariants =
      variants.length > 0 ? variants : [buildDefaultVariant(warehouses)];
    setSaving(true);
    setError(null);
    try {
      const activeOptions = options
        .map((option) => ({
          name: option.name.trim(),
          values: parseValues(option.values),
        }))
        .filter((option) => option.name && option.values.length > 0)
        .slice(0, 3);
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
        product_options_attributes: activeOptions.map((option, index) => ({
          name: option.name,
          position: index + 1,
          product_option_values_attributes: option.values.map(
            (value, valueIndex) => ({ value, position: valueIndex + 1 }),
          ),
        })) as never,
        product_images_attributes: draft.imageUrls
          .map((url, index) =>
            url.trim() ? { src: url.trim(), position: index + 1 } : null,
          )
          .filter(Boolean) as never,
        variants_attributes: validVariants.map((variant, index) => ({
          title: variant.title.trim() || "Default",
          sku: variant.sku.trim() || null,
          price: variant.price || "0.00",
          compare_at_price: variant.compare_at_price.trim() || null,
          cost: variant.cost_per_item.trim() || null,
          cost_per_item: variant.cost_per_item.trim() || null,
          barcode: variant.barcode.trim() || null,
          option1: variant.option1 || null,
          option2: variant.option2 || null,
          option3: variant.option3 || null,
          position: index + 1,
          inventory_policy: "deny",
          inventory_management: "shopify",
          requires_shipping: true,
          taxable: true,
          stock_items_attributes: warehouses.map((warehouse) => ({
            warehouse_id: warehouse.id,
            quantity_on_hand:
              parseInt(variant.stock[warehouse.id] || "0", 10) || 0,
            low_stock_threshold:
              parseInt(variant.threshold[warehouse.id] || "0", 10) || 0,
          })),
        })),
      });
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
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
                Options & variants
              </h2>
              <button
                type="button"
                onClick={generateVariants}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
              >
                Generate variants
              </button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {options.map((option, index) => (
                <div key={index} className="grid grid-cols-3 gap-2">
                  <input
                    value={option.name}
                    onChange={(e) =>
                      setOptions((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, name: e.target.value } : row,
                        ),
                      )
                    }
                    placeholder="Option"
                    className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
                  />
                  <input
                    value={option.values}
                    onChange={(e) =>
                      setOptions((prev) =>
                        prev.map((row, i) =>
                          i === index
                            ? { ...row, values: e.target.value }
                            : row,
                        ),
                      )
                    }
                    placeholder="Comma separated values"
                    className="col-span-2 rounded-lg border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
              ))}
            </div>
            <div className="overflow-x-auto rounded-lg border border-slate-200">
              <table className="min-w-full text-sm">
                <thead className="bg-slate-50 text-xs uppercase text-slate-500">
                  <tr>
                    <th className="px-3 py-2 text-left">Variant</th>
                    <th className="px-3 py-2 text-left">SKU</th>
                    <th className="px-3 py-2 text-right">Price</th>
                    <th className="px-3 py-2 text-right">Compare</th>
                    <th className="px-3 py-2 text-right">Cost</th>
                    {warehouses.map((warehouse) => (
                      <th key={warehouse.id} className="px-3 py-2 text-right">
                        {warehouse.code || warehouse.name}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {variants.map((variant, index) => (
                    <tr key={variant.key}>
                      <td className="px-3 py-2 min-w-44">
                        <input
                          value={variant.title}
                          onChange={(e) =>
                            updateVariant(index, { title: e.target.value })
                          }
                          className="w-full rounded border border-slate-300 px-2 py-1"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          value={variant.sku}
                          onChange={(e) =>
                            updateVariant(index, { sku: e.target.value })
                          }
                          className="w-32 rounded border border-slate-300 px-2 py-1 font-mono"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
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
                      {warehouses.map((warehouse) => (
                        <td key={warehouse.id} className="px-3 py-2">
                          <input
                            type="number"
                            min={0}
                            value={variant.stock[warehouse.id] || "0"}
                            onChange={(e) =>
                              updateVariantStock(
                                index,
                                warehouse.id,
                                e.target.value,
                              )
                            }
                            className="w-20 rounded border border-slate-300 px-2 py-1 text-right"
                          />
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="bg-white rounded-xl ring-1 ring-slate-200 p-5 space-y-3">
            <h2 className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
              Images
            </h2>
            {draft.imageUrls.map((url, index) => (
              <div key={index} className="flex gap-2">
                <input
                  value={url}
                  onChange={(e) =>
                    setField(
                      "imageUrls",
                      draft.imageUrls.map((row, i) =>
                        i === index ? e.target.value : row,
                      ),
                    )
                  }
                  placeholder="https://..."
                  className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm"
                />
                <button
                  type="button"
                  onClick={() =>
                    setField(
                      "imageUrls",
                      draft.imageUrls.filter((_, i) => i !== index),
                    )
                  }
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-600"
                >
                  Remove
                </button>
              </div>
            ))}
            <button
              type="button"
              onClick={() => setField("imageUrls", [...draft.imageUrls, ""])}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700"
            >
              Add image URL
            </button>
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
