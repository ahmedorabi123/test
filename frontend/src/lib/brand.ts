// Brand color tokens. Currently mirrors Tailwind's indigo scale so the existing
// UI looks unchanged while new components can opt into the `brand-*` aliases.
// Updating these values (and the matching `brand` palette in tailwind.config.js)
// re-skins the entire app.

export const BRAND_COLORS = {
  50:  "#eef2ff",
  100: "#e0e7ff",
  200: "#c7d2fe",
  300: "#a5b4fc",
  400: "#818cf8",
  500: "#6366f1",
  600: "#4f46e5",
  700: "#4338ca",
  800: "#3730a3",
  900: "#312e81",
} as const;

export const BRAND_NAME = "Zedzee ERP";
