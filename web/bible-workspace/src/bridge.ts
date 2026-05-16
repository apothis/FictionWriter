import type { BibleWorkspaceSnapshot } from "./types";

// JS↔Swift bridge contract for the Bible Workspace WKWebView.
//
// **Swift → JS**: Swift calls `window.loom.applySnapshot(<snapshot>)`
// via `webView.evaluateJavaScript(...)`. This module registers the
// global `window.loom` namespace and forwards snapshots to whichever
// React component is currently subscribed.
//
// **JS → Swift** (Session 2+): React components dispatch intents via
// `postIntent({ kind: "patchCharacter", ... })`, which marshals to
// the named `WKScriptMessageHandler` ("loom") for Swift to decode +
// dispatch through ProjectSession.

declare global {
  interface Window {
    loom: {
      applySnapshot: (snap: BibleWorkspaceSnapshot) => void;
    };
    webkit?: {
      messageHandlers: {
        loom?: {
          postMessage: (msg: unknown) => void;
        };
      };
    };
  }
}

type SnapshotSubscriber = (snap: BibleWorkspaceSnapshot) => void;

// Single-subscriber model — the App component subscribes once at
// mount. If we ever need fan-out (multiple components observing
// the same snapshot independently rather than via React context),
// trivial to extend to a Set<SnapshotSubscriber>.
let subscriber: SnapshotSubscriber | null = null;
// Buffer for snapshots that arrive before React mounts (race
// against the Swift `webView(_:didFinish:)` push — fires right
// after page-load, which is exactly when React is mounting).
let pendingSnapshot: BibleWorkspaceSnapshot | null = null;

window.loom = {
  applySnapshot(snap: BibleWorkspaceSnapshot) {
    if (subscriber) {
      subscriber(snap);
    } else {
      pendingSnapshot = snap;
    }
  },
};

export function subscribeToSnapshots(fn: SnapshotSubscriber): () => void {
  subscriber = fn;
  if (pendingSnapshot) {
    fn(pendingSnapshot);
    pendingSnapshot = null;
  }
  return () => {
    if (subscriber === fn) {
      subscriber = null;
    }
  };
}

// Session 2+ intent dispatch. Stubbed for Session 1 so the type is
// in place; called sites land in CharacterEditor / LorebookEditor.
export interface BibleWorkspaceIntent {
  kind: string;
  [k: string]: unknown;
}

export function postIntent(intent: BibleWorkspaceIntent): void {
  const handler = window.webkit?.messageHandlers?.loom;
  if (!handler) {
    console.warn("[loom-bridge] postIntent called but no Swift handler attached", intent);
    return;
  }
  handler.postMessage(intent);
}

// Dev-only browser-preview harness. In `vite dev` there is no Swift
// host to push a snapshot, so the webview would hang on "Awaiting
// first snapshot…". When DEV is set and no Swift handler is present,
// feed a mock snapshot. The dynamic import + `import.meta.env.DEV`
// guard means none of this — nor devMockSnapshot — reaches the
// production bundle (`vite build` sets DEV false, dead-code-eliminated).
if (import.meta.env.DEV && !window.webkit?.messageHandlers?.loom) {
  void import("./devMockSnapshot").then(({ devMockSnapshot }) => {
    window.loom.applySnapshot(devMockSnapshot);
  });
}
