import { useEffect, useState } from "react";
import type { SnapshotTemplateScene, TemplateScenePatch } from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";

// Phase 7.b.5 — template-scene editor. Mirrors ReferenceEditor.tsx
// exactly (same three editable fields, debounce shape, reset-on-id
// pattern). Different verb in the header action: "Extract" vs.
// "Ingest", and the disk-state pill reads "N beats on disk" rather
// than "N chunks on disk".
//
// Three editable fields (matching TemplateScenePatch):
// - Name (single line)
// - NSFW (toggle)
// - Body (large prose blob — the source scene the writer will
//   structurally imitate)
//
// Plus an "Extract" action that fires the Pass A beat-extraction
// pipeline against gemma4_2b. The button re-enables for "Re-extract"
// once the .beats.json sidecar exists.

interface Props {
  template: SnapshotTemplateScene;
  dispatchPatch: (patch: TemplateScenePatch) => void;
  onBack: () => void;
  onDelete: () => void;
  onExtract: () => void;
}

export function TemplateSceneEditor({
  template,
  dispatchPatch,
  onBack,
  onDelete,
  onExtract,
}: Props) {
  const [draft, setDraft] = useState<SnapshotTemplateScene>(template);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(template);
  }, [template.id]);

  const send = useDebouncedCallback(
    (patch: TemplateScenePatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof SnapshotTemplateScene>(
    field: K,
    value: SnapshotTemplateScene[K],
  ) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    if (field === "name") send({ name: value as string });
    else if (field === "nsfw") send({ nsfw: value as boolean });
    else if (field === "body") send({ body: value as string });
  }

  const extractStateLabel =
    draft.beatCount === null
      ? "Not yet extracted"
      : `${draft.beatCount} beat${draft.beatCount === 1 ? "" : "s"} on disk`;

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed template)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
        <Button variant="ghost" onClick={onExtract}>
          {draft.beatCount === null ? "Extract" : "Re-extract"}
        </Button>
        <Button variant="destructive" onClick={onDelete}>
          Delete template
        </Button>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="A short identifier shown in lists + generation logs."
            />
          </Field>
          <Field
            label="NSFW"
            hint="When set, generated scenes from this template inherit the flag."
          >
            <label className="inline-flex items-center gap-2 text-sm text-loom-fg">
              <input
                type="checkbox"
                checked={draft.nsfw}
                onChange={(e) => update("nsfw", e.target.checked)}
              />
              <span>marked NSFW</span>
            </label>
          </Field>
          <Field label="Extraction state">
            <p className="text-xs text-loom-fg-secondary">{extractStateLabel}</p>
          </Field>
        </Section>

        <Section
          title="Body"
          hint="The source scene. Pass A (beat extraction) chunks this into a structural skeleton; the writer reuses that skeleton with new characters and content when you invoke `Write scene from template`."
        >
          <Field label="Source scene">
            <Textarea
              rows={24}
              value={draft.body}
              onChange={(e) => update("body", e.target.value)}
            />
          </Field>
        </Section>
      </div>
    </div>
  );
}

// --------------------------------------------------------------
// Layout primitives — kept inline alongside ReferenceEditor /
// LorebookEditor / CharacterEditor. With this fourth user, hoisting
// these into `components/EditorLayout.tsx` is now overdue; tracked
// in HANDOFF.md §15.13 as a "Phase 7.b followon" cleanup.
// --------------------------------------------------------------

function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="mb-3 text-xs font-medium uppercase tracking-wider text-loom-fg-secondary">
        {title}
      </h2>
      {hint && (
        <p className="mb-3 text-[11px] text-loom-fg-tertiary">{hint}</p>
      )}
      <div className="space-y-3">{children}</div>
    </section>
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
    <div>
      <div className="mb-1 flex items-baseline justify-between">
        <label className="text-xs font-medium text-loom-fg-secondary">
          {label}
        </label>
        {hint && (
          <span className="ml-2 text-[10px] italic text-loom-fg-tertiary">
            {hint}
          </span>
        )}
      </div>
      {children}
    </div>
  );
}
