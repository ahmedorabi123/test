import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import ProductImageUploader from "./ProductImageUploader";
import { productsApi } from "../../api/products";

vi.mock("../../api/products", () => ({
  productsApi: {
    uploadImages: vi.fn(),
    deleteImage: vi.fn(),
  },
}));

describe("ProductImageUploader", () => {
  beforeEach(() => {
    vi.mocked(productsApi.uploadImages).mockReset();
    vi.mocked(productsApi.deleteImage).mockReset();
  });

  it("uploads files and renders returned previews", async () => {
    vi.mocked(productsApi.uploadImages).mockResolvedValue([
      {
        id: 1,
        filename: "tee.png",
        content_type: "image/png",
        byte_size: 12,
        url: "/rails/active_storage/blobs/tee.png",
      },
    ]);

    const { container } = render(<ProductImageUploader productId="p1" />);
    const file = new File(["img"], "tee.png", { type: "image/png" });
    const input = container.querySelector(
      'input[type="file"]',
    ) as HTMLInputElement;
    fireEvent.change(input, { target: { files: [file] } });

    await waitFor(() => {
      expect(productsApi.uploadImages).toHaveBeenCalledWith("p1", [file]);
    });
    expect(await screen.findByText("tee.png")).toBeInTheDocument();
  });

  it("deletes an existing image", async () => {
    vi.mocked(productsApi.deleteImage).mockResolvedValue(undefined);

    render(
      <ProductImageUploader
        productId="p1"
        initial={[
          {
            id: 7,
            filename: "old.png",
            content_type: "image/png",
            byte_size: 10,
            url: "/old.png",
          },
        ]}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "×" }));

    await waitFor(() => {
      expect(productsApi.deleteImage).toHaveBeenCalledWith("p1", 7);
    });
    expect(screen.queryByText("old.png")).not.toBeInTheDocument();
  });
});
