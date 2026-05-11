/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    screens: {
      xs: "480px",
      sm: "640px",
      md: "768px",
      lg: "1024px",
      xl: "1280px",
      "2xl": "1536px",
      "3xl": "1920px",
    },
    extend: {
      colors: {
        status: {
          success: "#047857",
          warning: "#b45309",
          danger: "#b91c1c",
          info: "#0369a1",
          neutral: "#475569",
        },
      },
    },
  },
  plugins: [],
};
