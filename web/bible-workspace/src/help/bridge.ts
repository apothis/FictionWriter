// JS-side bridge to Swift. Mirrors the existing bible-workspace +
// plannedProject + projectTools bridges:
//   - Swift → JS: `window.loomHelp.applySnapshot(snapshot)` (per-bundle global)
//   - JS → Swift: `window.webkit.messageHandlers.loom.postMessage(intent)`
//     (shared handler — the host routes by which WKWebView received it)

import type { HelpIntent, HelpSnapshot } from "./types";

declare global {
  interface Window {
    // Namespaced apart from `window.loom` / `window.loomWizard` /
    // `window.loomTools` — tsc compiles all four source trees
    // together, so the global must not collide.
    loomHelp: {
      applySnapshot: (snapshot: HelpSnapshot) => void;
    };
    // Same shape as the other bundles' bridges — match them exactly
    // so the Window declarations merge cleanly across the four
    // source trees.
    webkit?: {
      messageHandlers: {
        loom?: { postMessage: (msg: unknown) => void };
      };
    };
  }
}

type SnapshotListener = (snapshot: HelpSnapshot) => void;

let lastSnapshot: HelpSnapshot | null = null;
const listeners = new Set<SnapshotListener>();

// Register the global up front so a snapshot push that lands BEFORE
// React mounts isn't lost — `lastSnapshot` keeps the latest, and
// new subscribers receive it on subscribe.
window.loomHelp = {
  applySnapshot(snapshot: HelpSnapshot) {
    lastSnapshot = snapshot;
    for (const fn of listeners) {
      try {
        fn(snapshot);
      } catch (err) {
        // Don't let one listener's exception drop sibling listeners.
        // eslint-disable-next-line no-console
        console.error("[loomHelp] subscriber threw:", err);
      }
    }
  },
};

export function subscribeToSnapshot(fn: SnapshotListener): () => void {
  listeners.add(fn);
  if (lastSnapshot) fn(lastSnapshot);
  return () => {
    listeners.delete(fn);
  };
}

export function postIntent(intent: HelpIntent): void {
  const handler = window.webkit?.messageHandlers?.loom;
  if (!handler) {
    // eslint-disable-next-line no-console
    console.warn("[loomHelp] no message handler registered (running in dev?)", intent);
    return;
  }
  handler.postMessage(intent);
}
