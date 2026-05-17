import type {
  GeneratedOutline,
  PlannedProjectConfig,
  PlannedProjectSnapshot,
  Style,
} from "./types";

// JS↔Swift bridge for the Planned Project wizard webview.
//
// **Swift → JS**: the host calls `window.loomWizard.applyPlannedSnapshot(...)`
// (the style library + frameworks) and `window.loomWizard.resolveReply(...)`
// (the async reply to a request/reply intent).
//
// **JS → Swift**: the wizard runs two request/reply operations —
// `generateOutline` and `createPlannedProject`. `postRequest` marshals
// the intent to the named `WKScriptMessageHandler` ("loom") with a
// `requestId`; the returned Promise resolves when Swift calls
// `resolveReply` with the matching id.

interface ReplyEnvelope {
  requestId: string;
  ok: boolean;
  value?: unknown;
  error?: string;
}

declare global {
  interface Window {
    // Namespaced apart from the Bible Workspace bundle's `window.loom`
    // — the two are separate bundles that never co-load, but tsc
    // compiles both source trees together, so the global must not
    // collide. The JS→Swift handler name ("loom") is unrelated.
    loomWizard: {
      applyPlannedSnapshot: (snap: PlannedProjectSnapshot) => void;
      resolveReply: (envelope: ReplyEnvelope) => void;
    };
    webkit?: {
      messageHandlers: {
        loom?: { postMessage: (msg: unknown) => void };
      };
    };
  }
}

type SnapshotSubscriber = (snap: PlannedProjectSnapshot) => void;

let subscriber: SnapshotSubscriber | null = null;
let pendingSnapshot: PlannedProjectSnapshot | null = null;

const pendingRequests = new Map<
  string,
  { resolve: (v: unknown) => void; reject: (e: Error) => void }
>();

window.loomWizard = {
  applyPlannedSnapshot(snap: PlannedProjectSnapshot) {
    if (subscriber) {
      subscriber(snap);
    } else {
      pendingSnapshot = snap;
    }
  },
  resolveReply(envelope: ReplyEnvelope) {
    const entry = pendingRequests.get(envelope.requestId);
    if (!entry) {
      console.warn("[loom-wizard] resolveReply for unknown requestId", envelope.requestId);
      return;
    }
    pendingRequests.delete(envelope.requestId);
    if (envelope.ok) {
      entry.resolve(envelope.value);
    } else {
      entry.reject(new Error(envelope.error ?? "request failed"));
    }
  },
};

export function subscribeToPlannedSnapshots(fn: SnapshotSubscriber): () => void {
  subscriber = fn;
  if (pendingSnapshot) {
    fn(pendingSnapshot);
    pendingSnapshot = null;
  }
  return () => {
    if (subscriber === fn) subscriber = null;
  };
}

let requestCounter = 0;

function nextRequestId(): string {
  requestCounter += 1;
  return `req-${Date.now()}-${requestCounter}`;
}

function post(kind: string, payload: Record<string, unknown>): Promise<unknown> {
  const handler = window.webkit?.messageHandlers?.loom;
  const requestId = nextRequestId();
  return new Promise((resolve, reject) => {
    if (!handler) {
      if (import.meta.env.DEV) {
        void import("./devMock").then(({ devResolveRequest }) => {
          devResolveRequest(kind, payload).then(resolve, reject);
        });
        return;
      }
      reject(new Error("[loom-wizard] no Swift host attached"));
      return;
    }
    pendingRequests.set(requestId, { resolve, reject });
    handler.postMessage({ kind, requestId, ...payload });
  });
}

/// Run the staged outline pipeline on the writer model. Resolves with
/// the generated outline (manuscript + scenes) for the review step.
export function requestGenerateOutline(
  config: PlannedProjectConfig,
): Promise<GeneratedOutline> {
  return post("generateOutline", { config }) as Promise<GeneratedOutline>;
}

/// Write the (edited) outline to a new .loom bundle on disk and open
/// it. Resolves once the project has been created.
export function requestCreatePlannedProject(
  title: string,
  config: PlannedProjectConfig,
  outline: GeneratedOutline,
): Promise<void> {
  return post("createPlannedProject", { title, config, outline }) as Promise<void>;
}

/// Fire-and-forget intent — the style-library CRUD. Swift applies the
/// mutation to `styles.json` and re-pushes the snapshot. No reply.
function postFireAndForget(kind: string, payload: Record<string, unknown>): void {
  const handler = window.webkit?.messageHandlers?.loom;
  if (!handler) {
    if (import.meta.env.DEV) {
      console.info("[loom-wizard] dev: fire-and-forget intent", kind, payload);
    }
    return;
  }
  handler.postMessage({ kind, ...payload });
}

/// Create or replace a style in the app library (matched by id).
export function postUpsertStyle(style: Style): void {
  postFireAndForget("upsertStyle", { style });
}

/// Delete a style from the app library.
export function postDeleteStyle(id: string): void {
  postFireAndForget("deleteStyle", { id });
}

/// Ask the host to close this window — used by the standalone style
/// editor's "Done" button (when not running inside the wizard).
export function postCloseWindow(): void {
  postFireAndForget("closeWizardWindow", {});
}

// Dev-only browser-preview harness. In `vite dev` there is no Swift
// host to push a snapshot, so feed the mock. Guarded by
// `import.meta.env.DEV` so it never reaches the production bundle.
if (import.meta.env.DEV && !window.webkit?.messageHandlers?.loom) {
  void import("./devMock").then(({ devMockSnapshot }) => {
    window.loomWizard.applyPlannedSnapshot(devMockSnapshot);
  });
}
