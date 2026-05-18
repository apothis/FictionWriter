import type { ProjectToolsSnapshot } from "./types";

// JS↔Swift bridge for the project-tools webview bundle.
//
// **Swift → JS**: the host calls `window.loomTools.applyToolsSnapshot(...)`.
// **JS → Swift**: fire-and-forget intents (`setSceneFraming`,
// `setAntiSlopPhrases`) posted to the `loom` message handler.

declare global {
  interface Window {
    // Namespaced apart from `window.loom` / `window.loomWizard` — tsc
    // compiles all three source trees together, so the global must
    // not collide.
    loomTools: {
      applyToolsSnapshot: (snap: ProjectToolsSnapshot) => void;
    };
    webkit?: {
      messageHandlers: {
        loom?: { postMessage: (msg: unknown) => void };
      };
    };
  }
}

type SnapshotSubscriber = (snap: ProjectToolsSnapshot) => void;

let subscriber: SnapshotSubscriber | null = null;
let pendingSnapshot: ProjectToolsSnapshot | null = null;

window.loomTools = {
  applyToolsSnapshot(snap: ProjectToolsSnapshot) {
    if (subscriber) {
      subscriber(snap);
    } else {
      pendingSnapshot = snap;
    }
  },
};

export function subscribeToToolsSnapshots(fn: SnapshotSubscriber): () => void {
  subscriber = fn;
  if (pendingSnapshot) {
    fn(pendingSnapshot);
    pendingSnapshot = null;
  }
  return () => {
    if (subscriber === fn) subscriber = null;
  };
}

export function postIntent(intent: { kind: string; [k: string]: unknown }): void {
  const handler = window.webkit?.messageHandlers?.loom;
  if (!handler) {
    console.warn("[loom-tools] postIntent — no Swift handler attached", intent);
    return;
  }
  handler.postMessage(intent);
}

// Dev-only browser-preview harness. `vite dev` has no Swift host, so
// feed a mock snapshot. `#antislop` in the URL previews that tool;
// otherwise the framing tool. Guarded by DEV — never in production.
if (import.meta.env.DEV && !window.webkit?.messageHandlers?.loom) {
  void import("./devMock").then(({ devMockSnapshot }) => {
    window.loomTools.applyToolsSnapshot(
      devMockSnapshot(window.location.hash.includes("antislop")),
    );
  });
}
