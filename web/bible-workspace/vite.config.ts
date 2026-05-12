import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath, URL } from "node:url";

// Vite config for the Bible Workspace WKWebView bundle.
//
// `base: ""` produces relative asset paths — required because the
// bundle is loaded via `file://...` URL from the Loom.app bundle,
// not served from a host. Absolute paths like `/assets/...` would
// resolve to the filesystem root.
//
// `build.assetsInlineLimit: 0` keeps assets as separate files so
// SPM's `.copy()` resource processor handles them cleanly. The
// trade-off is more files in the bundle; for a Bible Workspace
// scoped pilot that's fine.
//
// `build.target: "es2022"` matches macOS 14+ WKWebView's JS engine.

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
    outDir: "dist",
    emptyOutDir: true,
    assetsInlineLimit: 0,
    // file:// loading: ES modules don't reliably execute under
    // file:// in WebKit (CORS rules apply differently; module fetch
    // can silently fail with no error event). The Bible Workspace
    // bundle is loaded via `webView.loadFileURL` so we have to
    // sidestep the module path entirely. IIFE output produces one
    // classic <script> tag; no module loading, no CORS, no async
    // import quirks. The post-build sed in
    // scripts/build-bible-workspace.sh strips type="module" from
    // the emitted script tag (Vite still writes it even for IIFE
    // builds).
    modulePreload: false,
    rollupOptions: {
      // IIFE format requires a single chunk — code splitting needs
      // dynamic import / module loading. Loom's workspace bundle is
      // small enough (~170KB) that single-chunk is fine.
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: "assets/[name].js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: "assets/[name].[ext]",
      },
    },
  },
});
