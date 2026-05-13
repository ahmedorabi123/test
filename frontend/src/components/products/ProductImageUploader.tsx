import { useEffect, useRef, useState } from "react";
import { productsApi, type UploadedImage } from "../../api/products";

interface Props {
  productId: string;
  initial?: UploadedImage[];
  onChange?: (images: UploadedImage[]) => void;
}

const ALLOWED = [
  "image/png",
  "image/jpeg",
  "image/jpg",
  "image/webp",
  "image/gif",
];
const MAX_BYTES = 5 * 1024 * 1024;

export default function ProductImageUploader({
  productId,
  initial = [],
  onChange,
}: Props) {
  const [images, setImages] = useState<UploadedImage[]>(initial);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    onChange?.(images);
  }, [images, onChange]);

  const upload = async (files: File[]) => {
    setError(null);
    const invalid = files.find(
      (f) => !ALLOWED.includes(f.type) || f.size > MAX_BYTES,
    );
    if (invalid) {
      setError(
        invalid.size > MAX_BYTES
          ? `${invalid.name} exceeds 5 MB`
          : `${invalid.name}: unsupported type ${invalid.type || "(unknown)"}`,
      );
      return;
    }
    setUploading(true);
    try {
      const updated = await productsApi.uploadImages(productId, files);
      setImages(updated);
    } catch (e) {
      const msg =
        (e as { response?: { data?: { error?: string } } })?.response?.data
          ?.error || (e as Error).message;
      setError(msg);
    } finally {
      setUploading(false);
    }
  };

  const remove = async (id: number) => {
    setError(null);
    try {
      await productsApi.deleteImage(productId, id);
      setImages((prev) => prev.filter((i) => i.id !== id));
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <div className="space-y-2">
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragOver(false);
          const files = Array.from(e.dataTransfer.files);
          if (files.length) upload(files);
        }}
        onClick={() => inputRef.current?.click()}
        className={`flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed px-4 py-6 text-sm transition ${
          dragOver
            ? "border-indigo-400 bg-indigo-50"
            : "border-slate-300 bg-slate-50 hover:bg-slate-100"
        }`}
      >
        <span className="text-slate-600">
          {uploading ? "Uploading…" : "Drag files here or click to upload"}
        </span>
        <span className="text-xs text-slate-400">
          PNG, JPEG, WEBP, GIF · up to 5 MB each
        </span>
        <input
          ref={inputRef}
          type="file"
          multiple
          accept={ALLOWED.join(",")}
          className="hidden"
          onChange={(e) => {
            const files = Array.from(e.target.files ?? []);
            if (files.length) upload(files);
            e.target.value = "";
          }}
        />
      </div>

      {error && (
        <div className="rounded-md bg-rose-50 border border-rose-200 text-rose-700 text-xs px-3 py-2">
          {error}
        </div>
      )}

      {images.length > 0 && (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {images.map((img) => (
            <div
              key={img.id}
              className="group relative rounded-lg border border-slate-200 bg-white"
            >
              <img
                src={img.url}
                alt={img.filename}
                className="aspect-square w-full rounded-lg object-cover"
              />
              <button
                type="button"
                onClick={() => remove(img.id)}
                className="absolute right-1 top-1 rounded-full bg-rose-600/90 px-2 py-0.5 text-xs text-white opacity-0 hover:bg-rose-600 group-hover:opacity-100"
              >
                ×
              </button>
              <div className="truncate px-2 py-1 text-[10px] text-slate-500">
                {img.filename}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
