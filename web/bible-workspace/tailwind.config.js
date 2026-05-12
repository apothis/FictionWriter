/** @type {import('tailwindcss').Config} */
// Tailwind config for the Bible Workspace. Theme palette + spacing
// scale references CSS custom properties exposed by the Swift side
// (BibleWorkspaceWindowController emits these onto :root mirroring
// DesignTokens.swift), so changes to the AppKit palette propagate
// to the web bundle without rebuilding.
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        "loom-bg": "var(--loom-bg-primary)",
        "loom-bg-elevated": "var(--loom-bg-elevated)",
        "loom-bg-input": "var(--loom-bg-input)",
        "loom-fg": "var(--loom-fg-primary)",
        "loom-fg-secondary": "var(--loom-fg-secondary)",
        "loom-fg-tertiary": "var(--loom-fg-tertiary)",
        "loom-accent": "var(--loom-fg-accent)",
        "loom-border": "var(--loom-border)",
      },
      fontFamily: {
        // System font stack — matches DesignTokens.Typography.body's
        // -apple-system family. AppKit's default; web bundle picks
        // up the same on macOS.
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "system-ui",
          "sans-serif",
        ],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
};
