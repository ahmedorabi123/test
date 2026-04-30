import { useEffect, useMemo, useState } from "react";
import {
  bomItemsApi,
  variantsApi,
  type BomItem,
  type Variant,
} from "../api/production";

export default function BomEditorPage() {
  const [variantQuery, setVariantQuery] = useState("");
  const [variantResults, setVariantResults] = useState<Variant[]>([]);
  const [parent, setParent] = useState<Variant | null>(null);

  useEffect(() => {
    const t = setTimeout(async () => {
      if (variantQuery.trim().length < 2) {
        setVariantResults([]);
        return;
      }
      try {
        const res = await variantsApi.search(variantQuery.trim());
        setVariantResults(res);
      } catch {
        /* ignore */
      }
    }, 250);
    return () => clearTimeout(t);
  }, [variantQuery]);

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">
          Bill of Materials
        </h1>
        <p className="text-sm text-slate-500 mt-1">
          Define component variants that are consumed to assemble a parent
          variant.
        </p>
      </div>

      <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2">
        <label className="text-xs font-medium text-slate-600">
          Parent variant
        </label>
        {parent ? (
          <div className="flex items-center justify-between border border-slate-300 rounded-lg px-3 py-2 text-sm bg-slate-50">
            <div>
              <div className="font-medium">{parent.product_title}</div>
              <div className="text-xs text-slate-500">
                {parent.sku}
                {parent.title ? ` · ${parent.title}` : ""}
              </div>
            </div>
            <button
              onClick={() => setParent(null)}
              className="text-xs text-rose-600 hover:underline"
            >
              Change
            </button>
          </div>
        ) : (
          <>
            <input
              type="text"
              value={variantQuery}
              onChange={(e) => setVariantQuery(e.target.value)}
              placeholder="Search SKU or product name…"
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
            />
            {variantResults.length > 0 && (
              <div className="border border-slate-200 rounded-lg max-h-48 overflow-auto divide-y divide-slate-100">
                {variantResults.map((v) => (
                  <button
                    key={v.id}
                    onClick={() => {
                      setParent(v);
                      setVariantQuery("");
                      setVariantResults([]);
                    }}
                    className="w-full text-left px-3 py-2 text-sm hover:bg-slate-50"
                  >
                    <div className="font-medium">{v.product_title}</div>
                    <div className="text-xs text-slate-500">
                      {v.sku}
                      {v.title ? ` · ${v.title}` : ""}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {parent && <BomEditor parent={parent} />}
    </div>
  );
}

function BomEditor({ parent }: { parent: Variant }) {
  const [items, setItems] = useState<BomItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useMemo(
    () => async () => {
      setLoading(true);
      setError(null);
      try {
        const res = await bomItemsApi.list(parent.id);
        setItems(res);
      } catch (e) {
        setError((e as Error).message || "Failed to load BOM");
      } finally {
        setLoading(false);
      }
    },
    [parent.id],
  );

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-medium">Components for {parent.sku}</h2>
      </div>

      {loading && <div className="text-sm text-slate-500">Loading…</div>}
      {error && <div className="text-sm text-rose-600">{error}</div>}

      <table className="w-full text-sm">
        <thead className="text-left text-xs text-slate-500 uppercase">
          <tr>
            <th className="py-2">Component</th>
            <th className="py-2">SKU</th>
            <th className="py-2 text-right">Quantity</th>
            <th className="py-2 text-right">Waste</th>
            <th className="py-2"></th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {items.map((bi) => (
            <BomRow
              key={bi.id}
              item={bi}
              parentId={parent.id}
              onChanged={load}
            />
          ))}
          {items.length === 0 && !loading && (
            <tr>
              <td
                colSpan={5}
                className="py-4 text-sm text-slate-500 text-center"
              >
                No components yet
              </td>
            </tr>
          )}
        </tbody>
      </table>

      <AddBomRow parentId={parent.id} onAdded={load} />
    </div>
  );
}

function BomRow({
  item,
  parentId,
  onChanged,
}: {
  item: BomItem;
  parentId: string;
  onChanged: () => void;
}) {
  const [qty, setQty] = useState<string>(item.quantity);
  const [waste, setWaste] = useState<string>(item.waste_factor);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    setSaving(true);
    try {
      await bomItemsApi.update(parentId, item.id, {
        quantity: parseFloat(qty),
        waste_factor: parseFloat(waste),
      });
      await onChanged();
    } catch (e) {
      alert((e as Error).message || "Failed to save");
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!window.confirm("Remove this component?")) return;
    await bomItemsApi.destroy(parentId, item.id);
    await onChanged();
  };

  return (
    <tr>
      <td className="py-2">
        <div className="font-medium">
          {item.component?.product_title || "—"}
        </div>
        <div className="text-xs text-slate-500">
          {item.component?.title || ""}
        </div>
      </td>
      <td className="py-2 text-slate-600">{item.component?.sku || "—"}</td>
      <td className="py-2 text-right">
        <input
          type="number"
          step="0.0001"
          value={qty}
          onChange={(e) => setQty(e.target.value)}
          className="w-24 border border-slate-300 rounded px-2 py-1 text-right"
        />
      </td>
      <td className="py-2 text-right">
        <input
          type="number"
          step="0.01"
          min="0"
          max="0.99"
          value={waste}
          onChange={(e) => setWaste(e.target.value)}
          className="w-20 border border-slate-300 rounded px-2 py-1 text-right"
        />
      </td>
      <td className="py-2 text-right space-x-2">
        <button
          onClick={save}
          disabled={saving}
          className="text-xs text-indigo-600 hover:underline disabled:opacity-60"
        >
          Save
        </button>
        <button
          onClick={remove}
          className="text-xs text-rose-600 hover:underline"
        >
          Remove
        </button>
      </td>
    </tr>
  );
}

function AddBomRow({
  parentId,
  onAdded,
}: {
  parentId: string;
  onAdded: () => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Variant[]>([]);
  const [picked, setPicked] = useState<Variant | null>(null);
  const [qty, setQty] = useState<number>(1);
  const [waste, setWaste] = useState<number>(0);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const t = setTimeout(async () => {
      if (query.trim().length < 2) {
        setResults([]);
        return;
      }
      try {
        const res = await variantsApi.search(query.trim());
        setResults(res.filter((v) => v.id !== parentId));
      } catch {
        /* ignore */
      }
    }, 250);
    return () => clearTimeout(t);
  }, [query, parentId]);

  const add = async () => {
    if (!picked || qty <= 0) return;
    setSaving(true);
    try {
      await bomItemsApi.create(parentId, {
        component_variant_id: picked.id,
        quantity: qty,
        waste_factor: waste,
      });
      setPicked(null);
      setQuery("");
      setQty(1);
      setWaste(0);
      await onAdded();
    } catch (e) {
      alert((e as Error).message || "Failed to add");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="border-t border-slate-200 pt-4 space-y-2">
      <div className="text-xs font-medium text-slate-600">Add component</div>
      {picked ? (
        <div className="flex items-center justify-between border border-slate-300 rounded-lg px-3 py-2 text-sm bg-slate-50">
          <div>
            <div className="font-medium">{picked.product_title}</div>
            <div className="text-xs text-slate-500">
              {picked.sku}
              {picked.title ? ` · ${picked.title}` : ""}
            </div>
          </div>
          <button
            onClick={() => setPicked(null)}
            className="text-xs text-rose-600 hover:underline"
          >
            Change
          </button>
        </div>
      ) : (
        <>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search SKU or product name…"
            className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"
          />
          {results.length > 0 && (
            <div className="border border-slate-200 rounded-lg max-h-40 overflow-auto divide-y divide-slate-100">
              {results.map((v) => (
                <button
                  key={v.id}
                  onClick={() => {
                    setPicked(v);
                    setQuery("");
                    setResults([]);
                  }}
                  className="w-full text-left px-3 py-2 text-sm hover:bg-slate-50"
                >
                  <div className="font-medium">{v.product_title}</div>
                  <div className="text-xs text-slate-500">
                    {v.sku}
                    {v.title ? ` · ${v.title}` : ""}
                  </div>
                </button>
              ))}
            </div>
          )}
        </>
      )}

      <div className="flex items-end gap-3">
        <div>
          <label className="text-xs text-slate-500">Quantity</label>
          <input
            type="number"
            step="0.0001"
            min="0.0001"
            value={qty}
            onChange={(e) => setQty(parseFloat(e.target.value || "0"))}
            className="block w-28 border border-slate-300 rounded px-2 py-1 text-right text-sm"
          />
        </div>
        <div>
          <label className="text-xs text-slate-500">
            Waste factor (0–0.99)
          </label>
          <input
            type="number"
            step="0.01"
            min="0"
            max="0.99"
            value={waste}
            onChange={(e) => setWaste(parseFloat(e.target.value || "0"))}
            className="block w-28 border border-slate-300 rounded px-2 py-1 text-right text-sm"
          />
        </div>
        <button
          onClick={add}
          disabled={!picked || saving}
          className="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-60"
        >
          {saving ? "Adding…" : "Add component"}
        </button>
      </div>
    </div>
  );
}
