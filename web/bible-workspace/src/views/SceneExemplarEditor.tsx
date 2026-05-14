import { useEffect, useState } from "react";
import type { SceneExemplarPatch, SnapshotSceneExemplar } from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";
import { Section, Field } from "../components/EditorLayout";

// Phase 8.b.6 — Scene Exemplar editor. Unified surface that joins
// the underlying Reference + Template by shared UUID. The single
// "Ingest" affordance fans out Swift-side to ingestReference (Phase 5
// chunking + Wegmann embed) AND extractTemplateScene (Phase 7 Pass-A
// skeleton). Edits apply to both halves in lockstep so the projection
// stays consistent.
//
// State badges:
// - `hasIndex`: chunks + vectors on disk (used by retrieval)
// - `hasBeats`: Pass-A skeleton on disk (used by "Write from
//   template")
// A fully-ingested exemplar shows both. Re-ingest after a body edit
// regenerates both sidecars.

interface Props {
  exemplar: SnapshotSceneExemplar;
  dispatchPatch: (patch: SceneExemplarPatch) => void;
  onBack: () => void;
  onDelete: () => void;
  onIngest: () => void;
  // Phase 8.b.7 — true while EITHER sub-pipeline (chunk+embed or
  // Pass-A extraction) is in flight for this exemplar's UUID. The
  // button flips to "Ingesting…" + disabled; the snapshot push on
  // completion clears it.
  isIngesting?: boolean;
}

export function SceneExemplarEditor({
  exemplar,
  dispatchPatch,
  onBack,
  onDelete,
  onIngest,
  isIngesting = false,
}: Props) {
  const [draft, setDraft] = useState<SnapshotSceneExemplar>(exemplar);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(exemplar);
  }, [exemplar.id]);

  const send = useDebouncedCallback(
    (patch: SceneExemplarPatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof SnapshotSceneExemplar>(
    field: K,
    value: SnapshotSceneExemplar[K],
  ) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    if (field === "name") send({ name: value as string });
    else if (field === "nsfw") send({ nsfw: value as boolean });
    else if (field === "body") send({ body: value as string });
  }

  // Read state booleans + counts from the server-current `exemplar`
  // prop (not `draft`) so the status pills refresh on snapshot push.
  const chunkLabel =
    exemplar.chunkCount == null
      ? "no chunks"
      : `${exemplar.chunkCount} chunk${exemplar.chunkCount === 1 ? "" : "s"}`;
  const beatLabel =
    exemplar.beatCount == null
      ? "no beats"
      : `${exemplar.beatCount} beat${exemplar.beatCount === 1 ? "" : "s"}`;
  const ingestButtonLabel = isIngesting
    ? "Ingesting…"
    : exemplar.hasIndex && exemplar.hasBeats
      ? "Re-ingest"
      : "Ingest";

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed scene exemplar)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
        <Button
          variant="ghost"
          onClick={onIngest}
          disabled={isIngesting}
        >
          {ingestButtonLabel}
        </Button>
        <Button variant="destructive" onClick={onDelete}>
          Delete exemplar
        </Button>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="A short identifier shown in the exemplar list."
            />
          </Field>
          <Field
            label="NSFW"
            hint="When set, the retriever may filter or weight this exemplar differently."
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
          <Field
            label="Ingest state"
            hint="One Ingest action runs both sub-pipelines (chunk+embed for retrieval, Pass-A extraction for the beat skeleton). Re-ingest after editing the body."
          >
            <div className="flex flex-wrap gap-2 text-xs">
              <span
                className={
                  "rounded border px-2 py-0.5 " +
                  (exemplar.hasIndex
                    ? "border-loom-border bg-loom-bg-secondary text-loom-fg"
                    : "border-loom-border-subtle text-loom-fg-tertiary")
                }
              >
                {exemplar.hasIndex ? "✓" : "○"} {chunkLabel} on disk
              </span>
              <span
                className={
                  "rounded border px-2 py-0.5 " +
                  (exemplar.hasBeats
                    ? "border-loom-border bg-loom-bg-secondary text-loom-fg"
                    : "border-loom-border-subtle text-loom-fg-tertiary")
                }
              >
                {exemplar.hasBeats ? "✓" : "○"} {beatLabel} on disk
              </span>
            </div>
          </Field>
        </Section>

        <Section
          title="Body"
          hint="The exemplar prose. Phase 5 retrieval chunks + embeds; Phase 7 Pass-A extracts a beat skeleton. Both sidecars regenerate on Re-ingest."
        >
          <Field label="Scene prose">
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
