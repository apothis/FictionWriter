import { useEffect, useState } from "react";
import type { SnapshotTemplateScene, TemplateScenePatch } from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";
import { Section, Field } from "../components/EditorLayout";

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
  // True while Pass-A extraction is in flight on the Swift side.
  // Surfaced through the workspace snapshot's
  // `extractingTemplateIds`.
  isExtracting: boolean;
}

export function TemplateSceneEditor({
  template,
  dispatchPatch,
  onBack,
  onDelete,
  onExtract,
  isExtracting,
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

  // Read beatCount from `template` (server-current), not `draft`.
  // Draft is synced only on id change so editable fields don't get
  // clobbered mid-typing; server-supplied fields like beatCount need
  // to track every snapshot push.
  const beatCount = template.beatCount;
  const extractStateLabel = isExtracting
    ? "Extracting beats… (gemma4_2b, ~10–30s)"
    : beatCount == null
      ? "Not yet extracted"
      : `${beatCount} beat${beatCount === 1 ? "" : "s"} on disk`;
  const extractButtonLabel = isExtracting
    ? "Extracting…"
    : beatCount == null
      ? "Extract"
      : "Re-extract";

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
        <Button
          variant="ghost"
          onClick={isExtracting ? undefined : onExtract}
          disabled={isExtracting}
        >
          {extractButtonLabel}
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

