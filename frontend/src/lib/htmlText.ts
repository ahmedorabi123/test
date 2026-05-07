export function htmlToText(value?: string | null): string {
  if (!value) return "";

  const withBreaks = value
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, "\n")
    .replace(/<li[^>]*>/gi, "- ");

  const parser = new DOMParser();
  const doc = parser.parseFromString(withBreaks, "text/html");
  doc
    .querySelectorAll("script, style, noscript")
    .forEach((node) => node.remove());

  return (doc.body.textContent || "")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
