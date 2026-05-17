import { useState } from "react";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Select } from "../components/ui/Select";
import { Textarea } from "../components/ui/Textarea";
import { postDeleteStyle, postUpsertStyle } from "./bridge";
import type { Style, StyleType } from "./types";

// The style-library editor — create / edit / delete the app-level
// styles that thread into generation (LOOM_PLANNED_PROJECT.md §4
// Phase 4 item 4). Mutations are fire-and-forget: each commit posts
// upsertStyle/deleteStyle and Swift re-pushes the snapshot. A local
// working copy keeps the UI responsive (and functional in the
// browser-preview harness, where there is no Swift host to persist).

function newStyle(): Style {
  return {
    id: crypto.randomUUID(),
    name: "New style",
    type: "genre",
    descriptor: "",
    constraints: [],
    exemplars: [],
    isBuiltIn: false,
  };
}

export function StyleEditor({
  initialStyles,
  onClose,
}: {
  initialStyles: Style[];
  onClose: () => void;
}) {
  const [styles, setStyles] = useState<Style[]>(initialStyles);

  function commit(style: Style) {
    setStyles((list) => list.map((s) => (s.id === style.id ? style : s)));
    postUpsertStyle(style);
  }

  function patchLocal(id: string, patch: Partial<Style>) {
    setStyles((list) => list.map((s) => (s.id === id ? { ...s, ...patch } : s)));
  }

  function addStyle() {
    const s = newStyle();
    setStyles((list) => [...list, s]);
    postUpsertStyle(s);
  }

  function removeStyle(id: string) {
    setStyles((list) => list.filter((s) => s.id !== id));
    postDeleteStyle(id);
  }

  return (
    <div className="flex h-screen flex-col bg-loom-bg text-loom-fg">
      <header className="flex items-center justify-between border-b border-loom-border px-8 py-3">
        <h1 className="text-lg font-semibold">Style library</h1>
        <div className="flex gap-2">
          <Button variant="ghost" onClick={addStyle}>
            New style
          </Button>
          <Button onClick={onClose}>Done</Button>
        </div>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-8 py-6">
        <div className="flex max-w-3xl flex-col gap-4">
          <p className="text-xs text-loom-fg-tertiary">
            Styles are shared across all projects. Genre and register are
            kept on separate prompt channels; the register section is
            framed as hard constraints.
          </p>
          {styles.length === 0 && (
            <p className="text-sm text-loom-fg-tertiary">
              No styles yet — add one to get started.
            </p>
          )}
          {styles.map((style) => (
            <StyleCard
              key={style.id}
              style={style}
              onPatch={(patch) => patchLocal(style.id, patch)}
              onCommit={() => commit(style)}
              onDelete={() => removeStyle(style.id)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function StyleCard({
  style,
  onPatch,
  onCommit,
  onDelete,
}: {
  style: Style;
  onPatch: (patch: Partial<Style>) => void;
  onCommit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-loom-border bg-loom-bg-elevated p-4">
      <div className="flex items-center gap-2">
        <Input
          className="font-medium"
          value={style.name}
          onChange={(e) => onPatch({ name: e.target.value })}
          onBlur={onCommit}
        />
        <Select
          className="w-32"
          value={style.type}
          onChange={(e) => {
            onPatch({ type: e.target.value as StyleType });
            // A select change has no blur-after-edit, commit inline.
            setTimeout(onCommit, 0);
          }}
        >
          <option value="genre">Genre</option>
          <option value="register">Register</option>
        </Select>
        {style.isBuiltIn && (
          <span className="shrink-0 whitespace-nowrap rounded bg-loom-bg-input px-2 py-0.5 text-xs text-loom-fg-tertiary">
            built-in
          </span>
        )}
        <Button variant="destructive" className="ml-auto" onClick={onDelete}>
          Delete
        </Button>
      </div>
      <Textarea
        rows={2}
        className="text-xs"
        placeholder="Descriptor — 2–4 sentences"
        value={style.descriptor}
        onChange={(e) => onPatch({ descriptor: e.target.value })}
        onBlur={onCommit}
      />
      <Textarea
        rows={3}
        className="text-xs"
        placeholder="Constraints — one per line"
        value={style.constraints.join("\n")}
        onChange={(e) =>
          onPatch({
            constraints: e.target.value.split("\n").map((l) => l.trim()).filter(Boolean),
          })
        }
        onBlur={onCommit}
      />
      <Textarea
        rows={2}
        className="text-xs"
        placeholder="Exemplars — one short passage per line (optional)"
        value={style.exemplars.join("\n")}
        onChange={(e) =>
          onPatch({
            exemplars: e.target.value.split("\n").map((l) => l.trim()).filter(Boolean),
          })
        }
        onBlur={onCommit}
      />
    </div>
  );
}
