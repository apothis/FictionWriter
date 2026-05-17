import { useState } from "react";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Select } from "../components/ui/Select";
import { Textarea } from "../components/ui/Textarea";
import { cn } from "../lib/cn";
import { postDeleteStyle, postUpsertStyle } from "./bridge";
import type { Style, StyleType } from "./types";

// The style-library editor — create / edit / mix / delete the
// app-level styles that thread into generation (LOOM_PLANNED_PROJECT
// §4 Phase 4 item 4). Two views: a card browser grouped by genre /
// register, and a per-style detail editor reached by clicking a card.
// Mutations are fire-and-forget: each commit posts upsertStyle/
// deleteStyle and Swift re-pushes the snapshot. A local working copy
// keeps the UI responsive (and functional in the browser-preview
// harness, where there is no Swift host to persist).

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
  const [selectedId, setSelectedId] = useState<string | null>(null);

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
    // Open the new (blank) style straight into the editor to fill in.
    setSelectedId(s.id);
  }

  function removeStyle(id: string) {
    setStyles((list) => list.filter((s) => s.id !== id));
    postDeleteStyle(id);
    setSelectedId(null);
  }

  const selected = styles.find((s) => s.id === selectedId) ?? null;

  if (selected) {
    return (
      <StyleDetail
        style={selected}
        onPatch={(patch) => patchLocal(selected.id, patch)}
        onCommit={() => commit(styles.find((s) => s.id === selected.id) ?? selected)}
        onDelete={() => removeStyle(selected.id)}
        onBack={() => setSelectedId(null)}
      />
    );
  }

  return (
    <StyleBrowser
      styles={styles}
      onSelect={setSelectedId}
      onNew={addStyle}
      onClose={onClose}
    />
  );
}

function StyleBrowser({
  styles,
  onSelect,
  onNew,
  onClose,
}: {
  styles: Style[];
  onSelect: (id: string) => void;
  onNew: () => void;
  onClose: () => void;
}) {
  const genres = styles.filter((s) => s.type === "genre");
  const registers = styles.filter((s) => s.type === "register");
  return (
    <div className="flex h-screen flex-col bg-loom-bg text-loom-fg">
      <header className="flex items-center justify-between border-b border-loom-border px-8 py-3">
        <h1 className="text-lg font-semibold">Style library</h1>
        <div className="flex gap-2">
          <Button variant="ghost" onClick={onNew}>
            New style
          </Button>
          <Button onClick={onClose}>Done</Button>
        </div>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-8 py-6">
        <div className="flex max-w-3xl flex-col gap-6">
          <p className="text-xs text-loom-fg-tertiary">
            Styles are shared across all projects. Genre and register are
            kept on separate prompt channels; the register section is
            framed as hard constraints. Click a style to edit it.
          </p>
          {styles.length === 0 && (
            <p className="text-sm text-loom-fg-tertiary">
              No styles yet — add one to get started.
            </p>
          )}
          <StyleGroup title="Genre" styles={genres} onSelect={onSelect} />
          <StyleGroup title="Register" styles={registers} onSelect={onSelect} />
        </div>
      </div>
    </div>
  );
}

function StyleGroup({
  title,
  styles,
  onSelect,
}: {
  title: string;
  styles: Style[];
  onSelect: (id: string) => void;
}) {
  if (styles.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      <h2 className="text-sm font-semibold text-loom-fg-secondary">{title}</h2>
      <div className="grid grid-cols-2 gap-2">
        {styles.map((s) => (
          <button
            key={s.id}
            type="button"
            onClick={() => onSelect(s.id)}
            className={cn(
              "rounded-lg border border-loom-border bg-loom-bg-elevated px-4 py-3 text-left transition-colors",
              "hover:bg-loom-bg-input",
            )}
          >
            <div className="flex items-center gap-2">
              <span className="font-medium">{s.name}</span>
              {s.isBuiltIn && (
                <span className="shrink-0 whitespace-nowrap rounded bg-loom-bg-input px-1.5 py-0.5 text-[10px] text-loom-fg-tertiary">
                  built-in
                </span>
              )}
            </div>
            <div className="mt-0.5 line-clamp-2 text-xs text-loom-fg-tertiary">
              {s.descriptor || "No descriptor yet."}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

function StyleDetail({
  style,
  onPatch,
  onCommit,
  onDelete,
  onBack,
}: {
  style: Style;
  onPatch: (patch: Partial<Style>) => void;
  onCommit: () => void;
  onDelete: () => void;
  onBack: () => void;
}) {
  return (
    <div className="flex h-screen flex-col bg-loom-bg text-loom-fg">
      <header className="flex items-center justify-between border-b border-loom-border px-8 py-3">
        <Button variant="ghost" onClick={onBack}>
          ‹ Style library
        </Button>
        <Button variant="destructive" onClick={onDelete}>
          Delete
        </Button>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-8 py-6">
        <div className="flex max-w-2xl flex-col gap-4">
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
                // A select change has no blur-after-edit; commit inline.
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
          </div>
          <Field label="Descriptor" hint="2–4 sentences naming the style.">
            <Textarea
              rows={3}
              value={style.descriptor}
              placeholder="Hard-boiled crime. Moral ambiguity, rain-slicked streets…"
              onChange={(e) => onPatch({ descriptor: e.target.value })}
              onBlur={onCommit}
            />
          </Field>
          <Field label="Constraints" hint="Concrete do/don't rules — one per line.">
            <Textarea
              rows={4}
              value={style.constraints.join("\n")}
              placeholder="Keep the narration cynical."
              onChange={(e) =>
                onPatch({
                  constraints: e.target.value
                    .split("\n")
                    .map((l) => l.trim())
                    .filter(Boolean),
                })
              }
              onBlur={onCommit}
            />
          </Field>
          <Field label="Exemplars" hint="Optional — one short passage per line.">
            <Textarea
              rows={3}
              value={style.exemplars.join("\n")}
              placeholder="The rain hadn't stopped since Tuesday."
              onChange={(e) =>
                onPatch({
                  exemplars: e.target.value
                    .split("\n")
                    .map((l) => l.trim())
                    .filter(Boolean),
                })
              }
              onBlur={onCommit}
            />
          </Field>
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium">{label}</span>
      {hint && <span className="text-xs text-loom-fg-tertiary">{hint}</span>}
      {children}
    </label>
  );
}
