import { useEffect, useRef, useState } from "react";
import { useNavigate, useParams, Link } from "react-router-dom";
import {
  collectionsApi,
  type Collection,
  type CollectionProduct,
} from "../api/collections";
import { productsApi, type Product } from "../api/products";
import { htmlToText } from "../lib/htmlText";

type Draft = Pick<
  Collection,
  | "title"
  | "handle"
  | "body_html"
  | "image"
  | "sort_order"
  | "published_at"
  | "published_scope"
>;

function toDraft(c: Collection): Draft {
  return {
    title: c.title,
    handle: c.handle,
    body_html: c.body_html ?? "",
    image: c.image ?? "",
    sort_order: c.sort_order ?? "manual",
    published_at: c.published_at ?? "",
    published_scope: c.published_scope ?? "web",
  };
}

function canAddProductToManualCollection(product: Product) {
  return !(
    product.read_only_origin ||
    product.source === "shopify" ||
    product.shopify_product_id
  );
}

export default function CollectionDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const isNew = id === "new";

  const [collection, setCollection] = useState<Collection | null>(null);
  const [draft, setDraft] = useState<Draft>({
    title: "",
    handle: "",
    body_html: "",
    image: "",
    sort_order: "manual",
    published_at: "",
    published_scope: "web",
  });
  const originalRef = useRef<string>("");

  const [loading, setLoading] = useState(!isNew);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [stagedProducts, setStagedProducts] = useState<Product[]>([]);

  // Product search for adding
  const [productSearch, setProductSearch] = useState("");
  const [productResults, setProductResults] = useState<Product[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [removingId, setRemovingId] = useState<string | null>(null);

  const isDirty =
    JSON.stringify(draft) !== originalRef.current || Boolean(imageFile);

  useEffect(() => {
    if (isNew) return;
    setLoading(true);
    collectionsApi
      .get(id!)
      .then((c) => {
        setCollection(c);
        const d = toDraft(c);
        setDraft(d);
        originalRef.current = JSON.stringify(d);
      })
      .catch((e) => setError((e as Error).message))
      .finally(() => setLoading(false));
  }, [id, isNew]);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      if (isNew) {
        const created = await collectionsApi.create({
          ...draft,
          kind: "custom",
        });
        if (imageFile) await collectionsApi.uploadImage(created.id, imageFile);
        for (const product of stagedProducts) {
          await collectionsApi.addProduct(created.id, product.id);
        }
        navigate(`/collections/${created.id}`, { replace: true });
      } else {
        const updated = await collectionsApi.update(id!, draft);
        if (imageFile) {
          await collectionsApi.uploadImage(id!, imageFile);
          setImageFile(null);
        }
        setCollection(updated);
        const d = toDraft(updated);
        setDraft(d);
        originalRef.current = JSON.stringify(d);
      }
    } catch (e) {
      setError((e as Error).message || "Save failed");
    } finally {
      setSaving(false);
    }
  };

  const handleDiscard = () => {
    if (isNew) {
      navigate("/collections");
    } else if (collection) {
      const d = toDraft(collection);
      setDraft(d);
      originalRef.current = JSON.stringify(d);
    }
  };

  const searchProducts = async (q: string) => {
    if (!q.trim()) {
      setProductResults([]);
      return;
    }
    setSearchLoading(true);
    try {
      const res = await productsApi.list({ search: q, per_page: 10 });
      // Filter out already-in-collection products
      const existingIds = new Set([
        ...(collection?.products ?? []).map((p: CollectionProduct) => p.id),
        ...stagedProducts.map((p) => p.id),
      ]);
      setProductResults(
        res.data.filter(
          (p) => !existingIds.has(p.id) && canAddProductToManualCollection(p),
        ),
      );
    } finally {
      setSearchLoading(false);
    }
  };

  const handleAddProduct = async (product: Product) => {
    if (isNew) {
      if (!canAddProductToManualCollection(product)) {
        setError("Shopify-managed products cannot be added manually.");
        return;
      }
      setStagedProducts((rows) => [...rows, product]);
      setProductSearch("");
      setProductResults([]);
      return;
    }

    if (!collection) return;
    if (!canAddProductToManualCollection(product)) {
      setError("Shopify-managed products cannot be added manually.");
      return;
    }
    try {
      const updated = await collectionsApi.addProduct(
        collection.id,
        product.id,
      );
      setCollection(updated);
      setProductSearch("");
      setProductResults([]);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const handleRemoveProduct = async (productId: string) => {
    if (isNew) {
      setStagedProducts((rows) => rows.filter((row) => row.id !== productId));
      return;
    }

    if (!collection) return;
    setRemovingId(productId);
    try {
      const updated = await collectionsApi.removeProduct(
        collection.id,
        productId,
      );
      setCollection(updated);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setRemovingId(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64 text-slate-400 text-sm">
        Loading…
      </div>
    );
  }

  const isReadOnly =
    !isNew &&
    (collection?.kind === "smart" ||
      Boolean(
        collection?.read_only_origin ||
        collection?.source === "shopify" ||
        collection?.shopify_collection_id,
      ));

  return (
    <div className="mx-auto max-w-3xl px-4 pb-24 sm:px-0">
      {/* Sticky save bar */}
      {(isDirty || isNew) && !isReadOnly && (
        <div className="sticky top-0 z-30 flex flex-col gap-3 border-b border-amber-200 bg-amber-50 px-4 py-3 shadow-sm sm:flex-row sm:items-center sm:px-6">
          <span className="text-sm text-amber-800 font-medium flex-1">
            {isNew
              ? "New collection — fill in details below"
              : "You have unsaved changes"}
          </span>
          <button
            onClick={handleDiscard}
            className="min-h-11 rounded-lg border border-slate-300 bg-white px-4 text-sm font-medium text-slate-700 hover:bg-slate-50"
          >
            Discard
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="min-h-11 rounded-lg bg-indigo-600 px-4 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {saving ? "Saving…" : isNew ? "Create" : "Save changes"}
          </button>
        </div>
      )}

      {/* Page header */}
      <div className="mb-6 mt-4 flex flex-wrap items-center gap-3">
        <Link
          to="/collections"
          className="text-slate-400 hover:text-slate-600 text-sm"
        >
          ← Collections
        </Link>
        <span className="text-slate-300">/</span>
        <h1 className="text-xl font-semibold text-slate-800">
          {isNew ? "New Collection" : (collection?.title ?? "…")}
        </h1>
        {!isNew && collection && (
          <span
            className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              collection.kind === "smart"
                ? "bg-purple-50 text-purple-700 ring-purple-600/20"
                : "bg-indigo-50 text-indigo-700 ring-indigo-600/20"
            }`}
          >
            {collection.kind === "custom" ? "Custom" : "Smart"}
          </span>
        )}
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {/* Read-only notice */}
      {isReadOnly && (
        <div className="mb-4 rounded-lg bg-purple-50 border border-purple-200 px-4 py-3 text-sm text-purple-800">
          This collection is managed by Shopify. Details and membership are
          synced from Shopify and cannot be edited here.
        </div>
      )}

      {/* Title + Description */}
      <div className="mb-4 space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200 sm:p-6">
        <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide">
          Details
        </h2>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Title <span className="text-rose-500">*</span>
          </label>
          <input
            value={draft.title}
            onChange={(e) => setDraft({ ...draft, title: e.target.value })}
            disabled={isReadOnly}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50 disabled:text-slate-500"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Handle
          </label>
          <input
            value={draft.handle}
            onChange={(e) => setDraft({ ...draft, handle: e.target.value })}
            disabled={isReadOnly}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50 disabled:text-slate-500"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Description
          </label>
          <textarea
            rows={4}
            value={draft.body_html ?? ""}
            onChange={(e) => setDraft({ ...draft, body_html: e.target.value })}
            disabled={isReadOnly}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50 disabled:text-slate-500"
          />
          {draft.body_html && (
            <div className="mt-3 rounded-lg bg-slate-50 px-3 py-2 text-sm text-slate-700 whitespace-pre-line ring-1 ring-slate-200">
              {htmlToText(draft.body_html)}
            </div>
          )}
        </div>
      </div>

      <div className="mb-4 space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200 sm:p-6">
        <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide">
          Media
        </h2>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Image URL
          </label>
          <input
            value={draft.image ?? ""}
            onChange={(e) => setDraft({ ...draft, image: e.target.value })}
            disabled={isReadOnly}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50 disabled:text-slate-500"
          />
          <div className="mt-3 flex flex-wrap items-center gap-3">
            <label className="inline-flex min-h-10 cursor-pointer items-center justify-center rounded-lg border border-slate-300 bg-white px-3 text-sm font-medium text-slate-700 hover:bg-slate-50">
              Upload image
              <input
                type="file"
                accept="image/png,image/jpeg,image/jpg,image/webp,image/gif"
                className="hidden"
                disabled={isReadOnly}
                onChange={(event) =>
                  setImageFile(event.target.files?.[0] ?? null)
                }
              />
            </label>
            {imageFile && (
              <span className="text-xs text-slate-500">{imageFile.name}</span>
            )}
          </div>
          {(imageFile || draft.image) && (
            <img
              src={
                imageFile ? URL.createObjectURL(imageFile) : draft.image || ""
              }
              alt={draft.title}
              className="mt-3 h-28 w-28 rounded object-cover ring-1 ring-slate-200"
            />
          )}
        </div>
      </div>

      {/* Visibility */}
      <div className="mb-4 space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200 sm:p-6">
        <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide">
          Visibility
        </h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Published date
            </label>
            <input
              type="datetime-local"
              value={
                draft.published_at
                  ? draft.published_at.replace("Z", "").slice(0, 16)
                  : ""
              }
              onChange={(e) =>
                setDraft({
                  ...draft,
                  published_at: e.target.value
                    ? new Date(e.target.value).toISOString()
                    : null,
                })
              }
              disabled={isReadOnly}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 mb-1">
              Scope
            </label>
            <select
              value={draft.published_scope ?? "web"}
              onChange={(e) =>
                setDraft({ ...draft, published_scope: e.target.value })
              }
              disabled={isReadOnly}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50"
            >
              <option value="web">Online Store</option>
              <option value="global">Global</option>
            </select>
          </div>
        </div>
      </div>

      <div className="mb-4 space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200 sm:p-6">
        <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide">
          Sorting
        </h2>
        <div>
          <label className="block text-xs font-medium text-slate-600 mb-1">
            Sort order
          </label>
          <select
            value={draft.sort_order ?? "manual"}
            onChange={(e) => setDraft({ ...draft, sort_order: e.target.value })}
            disabled={isReadOnly}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:bg-slate-50"
          >
            <option value="manual">Manual</option>
            <option value="best-selling">Best selling</option>
            <option value="alpha-asc">Alphabetically, A-Z</option>
            <option value="alpha-desc">Alphabetically, Z-A</option>
            <option value="price-asc">Price, low to high</option>
            <option value="price-desc">Price, high to low</option>
            <option value="created-desc">Newest first</option>
          </select>
        </div>
      </div>

      {/* Smart collection rules (read-only JSON display) */}
      {isReadOnly && collection?.rules && collection.rules.length > 0 && (
        <div className="bg-white rounded-xl ring-1 ring-slate-200 p-6 mb-4">
          <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide mb-3">
            Rules
          </h2>
          <div className="overflow-x-auto rounded-lg bg-slate-50 p-3">
            <pre className="text-xs text-slate-700 whitespace-pre-wrap">
              {JSON.stringify(collection.rules, null, 2)}
            </pre>
          </div>
          <p className="text-xs text-slate-500 mt-2">
            Rules are managed in Shopify and synced here automatically.
          </p>
        </div>
      )}

      {/* Products section (only for custom or show-only for smart) */}
      {(isNew || collection) && (
        <div className="bg-white rounded-xl ring-1 ring-slate-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-slate-700 uppercase tracking-wide">
              Products (
              {isNew ? stagedProducts.length : collection?.products_count})
            </h2>
          </div>

          {/* Add product (custom only) */}
          {!isReadOnly && (
            <div className="mb-4">
              <div className="relative">
                <input
                  value={productSearch}
                  onChange={(e) => {
                    setProductSearch(e.target.value);
                    searchProducts(e.target.value);
                  }}
                  placeholder="Search and add products…"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
                {searchLoading && (
                  <span className="absolute right-3 top-2 text-slate-400 text-xs">
                    Searching…
                  </span>
                )}
              </div>
              {productResults.length > 0 && (
                <div className="mt-1 rounded-lg border border-slate-200 bg-white shadow-lg divide-y divide-slate-100 max-h-48 overflow-y-auto">
                  {productResults.map((p) => (
                    <button
                      key={p.id}
                      onClick={() => handleAddProduct(p)}
                      className="w-full flex items-center gap-3 px-3 py-2 text-sm text-slate-700 hover:bg-slate-50 text-left"
                    >
                      <span className="font-medium">{p.title}</span>
                      <span className="text-slate-400 font-mono text-xs">
                        {p.handle}
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Product list */}
          {(isNew ? stagedProducts : (collection?.products ?? [])).length >
          0 ? (
            <div className="divide-y divide-slate-100">
              {(isNew ? stagedProducts : (collection?.products ?? [])).map(
                (p: Product | CollectionProduct) => (
                  <div
                    key={p.id}
                    className="flex items-center gap-3 py-2.5 group"
                  >
                    <div className="flex-1 min-w-0">
                      <Link
                        to={`/products/${p.id}`}
                        className="text-sm font-medium text-indigo-700 hover:underline"
                      >
                        {p.title}
                      </Link>
                      <div className="text-xs text-slate-500 font-mono">
                        {p.handle}
                      </div>
                    </div>
                    <span
                      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
                        p.status === "active"
                          ? "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
                          : "bg-gray-100 text-gray-600 ring-gray-500/20"
                      }`}
                    >
                      {p.status}
                    </span>
                    {!isReadOnly && (
                      <button
                        onClick={() => handleRemoveProduct(p.id)}
                        disabled={removingId === p.id}
                        className="opacity-0 group-hover:opacity-100 text-red-500 hover:text-red-700 text-xs px-2 py-1 rounded transition-opacity disabled:opacity-50"
                      >
                        Remove
                      </button>
                    )}
                  </div>
                ),
              )}
            </div>
          ) : (
            <p className="text-sm text-slate-400 py-4 text-center">
              No products in this collection yet.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
