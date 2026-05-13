import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { Modal } from "./Modal";

describe("Modal", () => {
  it("does not render when closed", () => {
    render(
      <Modal open={false} onClose={() => undefined} title="x">
        <p>hidden</p>
      </Modal>,
    );
    expect(screen.queryByText("hidden")).not.toBeInTheDocument();
  });

  it("renders title, description, and content when open", () => {
    render(
      <Modal
        open
        onClose={() => undefined}
        title="My title"
        description="my desc"
      >
        <p>visible</p>
      </Modal>,
    );
    expect(screen.getByText("My title")).toBeInTheDocument();
    expect(screen.getByText("my desc")).toBeInTheDocument();
    expect(screen.getByText("visible")).toBeInTheDocument();
    expect(screen.getByRole("dialog")).toHaveAttribute("aria-modal", "true");
  });

  it("closes on Escape", async () => {
    const onClose = vi.fn();
    render(
      <Modal open onClose={onClose} title="x">
        <p>content</p>
      </Modal>,
    );
    await userEvent.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalled();
  });

  it("closes when backdrop button is clicked", async () => {
    const onClose = vi.fn();
    render(
      <Modal open onClose={onClose} title="x">
        <p>content</p>
      </Modal>,
    );
    await userEvent.click(screen.getByRole("button", { name: /Close modal/i }));
    expect(onClose).toHaveBeenCalled();
  });

  it("does not close on backdrop when closeOnBackdrop=false", async () => {
    const onClose = vi.fn();
    render(
      <Modal open onClose={onClose} title="x" closeOnBackdrop={false}>
        <p>content</p>
      </Modal>,
    );
    await userEvent.click(screen.getByRole("button", { name: /Close modal/i }));
    expect(onClose).not.toHaveBeenCalled();
  });
});
