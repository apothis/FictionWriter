import { useEffect, useState } from "react";
import type { ProjectToolsSnapshot } from "./types";
import { postIntent, subscribeToToolsSnapshots } from "./bridge";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";

// Project-tools webview — one bundle, two surfaces. The pushed
// snapshot's `tool` field selects which editor renders.

export function ToolsApp() {
  const [snapshot, setSnapshot] = useState<ProjectToolsSnapshot | null>(null);

  useEffect(() => subscribeToToolsSnapshots(setSnapshot), []);

  if (!snapshot) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-loom-fg-tertiary">
        Awaiting data from Loom…
      </div>
    );
  }

  if (snapshot.tool === "antislop") {
    return <AntiSlopEditor snapshot={snapshot} />;
  }
  return <FramingEditor snapshot={snapshot} />;
}

// MARK: - Scene framing

function FramingEditor({ snapshot }: { snapshot: ProjectToolsSnapshot }) {
  const [draft, setDraft] = useState(snapshot.framing);
  const [undressed, setUndressed] = useState<string[]>(
    snapshot.undressedCharacterIds,
  );

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(snapshot.framing);
    setUndressed(snapshot.undressedCharacterIds);
  }, [snapshot.sceneId]);

  const send = useDebouncedCallback((text: string) => {
    if (snapshot.sceneId) {
      postIntent({ kind: "setSceneFraming", sceneId: snapshot.sceneId, framing: text });
    }
  }, 300);

  function toggleUndressed(id: string) {
    const next = undressed.includes(id)
      ? undressed.filter((c) => c !== id)
      : [...undressed, id];
    setUndressed(next);
    if (snapshot.sceneId) {
      postIntent({
        kind: "setSceneUndressed",
        sceneId: snapshot.sceneId,
        characterIds: next,
      });
    }
  }

  return (
    <div className="flex h-full flex-col">
      <header className="border-b border-loom-border px-6 py-3">
        <h1 className="text-sm font-medium text-loom-fg">Scene Framing</h1>
        <p className="mt-0.5 text-xs text-loom-fg-tertiary">
          {snapshot.sceneTitle || "(untitled scene)"}
        </p>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <p className="mb-3 text-xs leading-relaxed text-loom-fg-secondary">
          The scenario for this scene — the dynamic, what's at stake, the
          intended intensity. Injected near the cursor at generation time as
          authorial direction. Unlike Notes, this reaches the model.
        </p>
        <Textarea
          rows={12}
          value={draft}
          placeholder="e.g. A first-time scene between established characters; tender, slow, earthy register. She is nervous; he is letting her set the pace."
          onChange={(e) => {
            setDraft(e.target.value);
            send(e.target.value);
          }}
        />
        {snapshot.sceneCharacters.length > 0 && (
          <div className="mt-5">
            <h2 className="text-xs font-medium text-loom-fg">
              Undressed in this scene
            </h2>
            <p className="mt-0.5 mb-2 text-[11px] leading-relaxed text-loom-fg-tertiary">
              Marks a character undressed so their concealed anatomy can be
              used. A deterministic signal — use it when the prose undresses
              someone without the obvious words (the auto-detector may miss it).
            </p>
            <div className="space-y-1">
              {snapshot.sceneCharacters.map((c) => (
                <label
                  key={c.id}
                  className="flex items-center gap-2 text-sm text-loom-fg"
                >
                  <input
                    type="checkbox"
                    checked={undressed.includes(c.id)}
                    onChange={() => toggleUndressed(c.id)}
                  />
                  <span>{c.name || "(unnamed)"}</span>
                </label>
              ))}
            </div>
          </div>
        )}
        <p className="mt-4 text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </p>
      </div>
    </div>
  );
}

// MARK: - Anti-slop list

function AntiSlopEditor({ snapshot }: { snapshot: ProjectToolsSnapshot }) {
  const [phrases, setPhrases] = useState<string[]>(snapshot.antiSlopPhrases);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => setPhrases(snapshot.antiSlopPhrases), [snapshot.projectTitle]);

  const send = useDebouncedCallback((next: string[]) => {
    postIntent({ kind: "setAntiSlopPhrases", phrases: next });
  }, 300);

  function commit(next: string[]) {
    setPhrases(next);
    send(next);
  }

  return (
    <div className="flex h-full flex-col">
      <header className="border-b border-loom-border px-6 py-3">
        <h1 className="text-sm font-medium text-loom-fg">Anti-slop List</h1>
        <p className="mt-0.5 text-xs text-loom-fg-tertiary">
          {snapshot.projectTitle} · {phrases.length} phrase
          {phrases.length === 1 ? "" : "s"}
        </p>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <p className="mb-3 text-xs leading-relaxed text-loom-fg-secondary">
          Cliché phrasings to discourage. A curated, editable list seeded from
          Loom's defaults — tune it for this project.
        </p>
        <div className="space-y-2">
          {phrases.map((phrase, i) => (
            <div key={i} className="flex gap-2">
              <Input
                value={phrase}
                placeholder="cliché phrase"
                onChange={(e) => {
                  const next = [...phrases];
                  next[i] = e.target.value;
                  commit(next);
                }}
              />
              <Button
                variant="ghost"
                onClick={() => commit(phrases.filter((_, j) => j !== i))}
                aria-label="Remove phrase"
              >
                ✕
              </Button>
            </div>
          ))}
          <Button variant="ghost" onClick={() => commit([...phrases, ""])}>
            + Add phrase
          </Button>
        </div>
        <p className="mt-4 text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </p>
      </div>
    </div>
  );
}
