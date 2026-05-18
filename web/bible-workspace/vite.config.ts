import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath, URL } from "node:url";

// Vite config for Loom's two WKWebView bundles — the Bible Workspace
// (`index.html`) and the Planned Project wizard (`plannedProject.html`).
//
// `base: ""` produces relative asset paths — required because the
// bundles load via `file://...` URLs from the Loom.app bundle, not
// from a host. Absolute paths like `/assets/...` would resolve to the
// filesystem root.
//
// `build.assetsInlineLimit: 0` keeps assets as separate files so
// SPM's `.copy()` resource processor handles them cleanly.
//
// `build.target: "es2022"` matches macOS 14+ WKWebView's JS engine.
//
// IIFE output can't code-split across multiple inputs, so each bundle
// is a separate `vite build` invocation selected by the `LOOM_BUNDLE`
// env var (see scripts/build-bible-workspace.sh). `vite dev` serves
// both HTML files natively — the split only matters for the build.

// One entry per WKWebView bundle. Selected by the LOOM_BUNDLE env var
// (see scripts/build-bible-workspace.sh); `index` is the default.
const BUNDLES: Record<string, { html: string; name: string; out: string }> = {
  index: { html: "index.html", name: "index", out: "dist" },
  plannedProject: {
    html: "plannedProject.html",
    name: "plannedProject",
    out: "dist-planned",
  },
  projectTools: {
    html: "projectTools.html",
    name: "projectTools",
    out: "dist-tools",
  },
};
const bundle = BUNDLES[process.env.LOOM_BUNDLE ?? "index"] ?? BUNDLES.index;
const entryHTML = bundle.html;
const entryName = bundle.name;

export default defineConfig({
  plugins: [react()],
  base: "",
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    target: "es2022",
    outDir: bundle.out,
    emptyOutDir: true,
    assetsInlineLimit: 0,
    // file:// loading: ES modules don't reliably execute under
    // file:// in WebKit (CORS rules apply differently; module fetch
    // can silently fail with no error event). The bundles load via
    // `webView.loadFileURL` so we sidestep the module path entirely.
    // IIFE output produces one classic <script> tag; no module
    // loading, no CORS, no async import quirks. The post-build sed in
    // scripts/build-bible-workspace.sh strips type="module" from the
    // emitted script tag (Vite still writes it even for IIFE builds).
    modulePreload: false,
    rollupOptions: {
      input: entryHTML,
      // IIFE format requires a single chunk — code splitting needs
      // dynamic import / module loading. Each bundle is small enough
      // (~170KB) that single-chunk is fine.
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: `assets/${entryName}.js`,
        chunkFileNames: `assets/${entryName}.js`,
        assetFileNames: "assets/[name].[ext]",
      },
    },
  },
});
