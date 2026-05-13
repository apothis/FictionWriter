import { useEffect, useState } from "react";
import type { ReferencePatch, SnapshotReference } from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";

// Phase 5 production A2.1 — reference-text editor. Mirrors the
// LorebookEditor structure: local draft + debounced dispatch; reset
// effect keyed on reference.id only.
//
// Three editable fields (matching `ReferencePatch`):
// - Name (single line)
// - NSFW (toggle; retrieval can filter on this flag)
// - Body (large prose blob — the actual reference text)
//
// Plus an "Ingest" action that fires the embed pipeline. The button
// is enabled regardless of current ingest state: re-ingesting after
// a body edit is the correct operation (the existing `.index`
// sidecar gets overwritten with new chunks + vectors). Ingest runs
// asynchronously on a background queue Swift-side; the snapshot
// pushes again on completion, surfacing the new chunk count.

interface Props {
  reference: SnapshotReference;
  dispatchPatch: (patch: ReferencePatch) => void;
  onBack: () => void;
  onDelete: () => void;
  onIngest: () => void;
}

export function ReferenceEditor({
  reference,
  dispatchPatch,
  onBack,
  onDelete,
  onIngest,
}: Props) {
  const [draft, setDraft] = useState<SnapshotReference>(reference);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(reference);
  }, [reference.id]);

  const send = useDebouncedCallback(
    (patch: ReferencePatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof SnapshotReference>(
    field: K,
    value: SnapshotReference[K],
  ) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    // Map snapshot field → patch field. Only name / nsfw / body are
    // patchable; the others (id, createdAt, chunkCount) are read-only.
    if (field === "name") send({ name: value as string });
    else if (field === "nsfw") send({ nsfw: value as boolean });
    else if (field === "body") send({ body: value as string });
  }

  const ingestStateLabel =
    draft.chunkCount === null
      ? "Not yet ingested"
      : `${draft.chunkCount} chunk${draft.chunkCount === 1 ? "" : "s"} on disk`;

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed reference)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
        <Button variant="ghost" onClick={onIngest}>
          {draft.chunkCount === null ? "Ingest" : "Re-ingest"}
        </Button>
        <Button variant="destructive" onClick={onDelete}>
          Delete reference
        </Button>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="A short identifier shown in lists + retrieval provenance."
            />
          </Field>
          <Field
            label="NSFW"
            hint="When set, the retriever may filter or weight this reference differently. Content-neutral at retrieval; only the flag is consulted."
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
          <Field label="Ingest state">
            <p className="text-xs text-loom-fg-secondary">{ingestStateLabel}</p>
          </Field>
        </Section>

        <Section
          title="Body"
          hint="The reference prose. The Phase 5 retriever chunks, classifies modality, and embeds this for style-RAG."
        >
          <Field label="Reference text">
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
// Layout primitives — copied from LorebookEditor / CharacterEditor.
// Per the LorebookEditor comment, these'll be worth extracting once
// there's a third user. References makes that third user — but
// landing it inline first keeps the diff focused; a follow-up commit
// can hoist Section/Field into `components/EditorLayout.tsx`.
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
