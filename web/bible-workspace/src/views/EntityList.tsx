import type {
  BibleWorkspaceSnapshot,
  Character,
  LorebookEntry,
  PendingSuggestion,
  SnapshotReference,
  SnapshotSceneExemplar,
  SnapshotTemplateScene,
} from "../types";
import { cn } from "../lib/cn";

// Session 1: read-only entity list rendering. Characters + lorebook
// + a summary strip showing scene count and pending-suggestion
// count. No editing affordances — those land in Sessions 2-5.

interface Props {
  snapshot: BibleWorkspaceSnapshot;
  onSelectCharacter: (id: string) => void;
  onSelectLorebookEntry: (id: string) => void;
  onSelectReference: (id: string) => void;
  onSelectTemplateScene: (id: string) => void;
  onSelectSceneExemplar: (id: string) => void;
  onAddLorebookEntry: () => void;
  onAddReference: () => void;
  onAddTemplateScene: () => void;
  onAddSceneExemplar: () => void;
  onOpenSuggestions: () => void;
  onOpenEntityProposals: () => void;
  onOpenRelationshipProposals: () => void;
  onOpenRelationshipMatrix: () => void;
  onOpenRelationshipGraph: () => void;
}

export function EntityList({
  snapshot,
  onSelectCharacter,
  onSelectLorebookEntry,
  onSelectReference,
  onSelectTemplateScene,
  onSelectSceneExemplar,
  onAddLorebookEntry,
  onAddReference,
  onAddTemplateScene,
  onAddSceneExemplar,
  onOpenSuggestions,
  onOpenEntityProposals,
  onOpenRelationshipProposals,
  onOpenRelationshipMatrix,
  onOpenRelationshipGraph,
}: Props) {
  const sceneExemplars = snapshot.sceneExemplars ?? [];
  return (
    <div className="flex h-full flex-col">
      <Header
        snapshot={snapshot}
        onOpenSuggestions={onOpenSuggestions}
        onOpenEntityProposals={onOpenEntityProposals}
        onOpenRelationshipProposals={onOpenRelationshipProposals}
      />
      <div className="flex-1 overflow-auto">
        <Section
          title="Characters"
          count={snapshot.characters.length}
          headerAction={
            snapshot.characters.length >= 2 ? (
              <span className="flex gap-3">
                <button
                  type="button"
                  onClick={onOpenRelationshipGraph}
                  className="text-xs text-loom-accent hover:underline"
                >
                  Relationship map →
                </button>
                <button
                  type="button"
                  onClick={onOpenRelationshipMatrix}
                  className="text-xs text-loom-accent hover:underline"
                >
                  Matrix →
                </button>
              </span>
            ) : undefined
          }
        >
          {snapshot.characters.length === 0 ? (
            <EmptyRow text="No characters yet. Add some via the inspector." />
          ) : (
            snapshot.characters.map((c) => (
              <CharacterRow
                key={c.id}
                character={c}
                pendingSuggestions={snapshot.suggestions.filter(
                  (s) => s.characterId === c.id,
                )}
                onClick={() => onSelectCharacter(c.id)}
              />
            ))
          )}
        </Section>
        <Section
          title="Lorebook"
          count={snapshot.lorebook.length}
          headerAction={
            <button
              type="button"
              onClick={onAddLorebookEntry}
              className="text-xs text-loom-accent hover:underline"
            >
              + Add entry
            </button>
          }
        >
          {snapshot.lorebook.length === 0 ? (
            <EmptyRow text="No lorebook entries yet." />
          ) : (
            snapshot.lorebook.map((entry) => (
              <LorebookRow
                key={entry.id}
                entry={entry}
                onClick={() => onSelectLorebookEntry(entry.id)}
              />
            ))
          )}
        </Section>
        <Section
          title="Scene Exemplars"
          count={sceneExemplars.length}
          headerAction={
            <AddButton
              label="+ Add scene exemplar"
              onClick={onAddSceneExemplar}
              enabled={snapshot.isProjectOnDisk !== false}
              disabledHint="Save the project (⌘S) to add scene exemplars — they're stored on disk."
            />
          }
        >
          {sceneExemplars.length === 0 ? (
            <EmptyRow text="No scene exemplars yet. A scene exemplar is one prose body that contributes BOTH retrieval chunks (Phase 5) AND a beat skeleton (Phase 7) to generation. One paste, two sidecars." />
          ) : (
            sceneExemplars.map((ex) => (
              <SceneExemplarRow
                key={ex.id}
                exemplar={ex}
                onClick={() => onSelectSceneExemplar(ex.id)}
              />
            ))
          )}
        </Section>
        <Section
          title="References"
          count={snapshot.references.length}
          headerAction={
            <AddButton
              label="+ Add reference"
              onClick={onAddReference}
              enabled={snapshot.isProjectOnDisk !== false}
              disabledHint="Save the project (⌘S) to add references — they're stored on disk."
            />
          }
        >
          {snapshot.references.length === 0 ? (
            <EmptyRow text="No reference texts yet. Reference texts feed the Phase 5 style-RAG retriever." />
          ) : (
            snapshot.references.map((ref) => (
              <ReferenceRow
                key={ref.id}
                reference={ref}
                onClick={() => onSelectReference(ref.id)}
              />
            ))
          )}
        </Section>
        <Section
          title="Template Scenes"
          count={snapshot.templateScenes.length}
          headerAction={
            <AddButton
              label="+ Add template"
              onClick={onAddTemplateScene}
              enabled={snapshot.isProjectOnDisk !== false}
              disabledHint="Save the project (⌘S) to add template scenes — they're stored on disk."
            />
          }
        >
          {snapshot.templateScenes.length === 0 ? (
            <EmptyRow text="No template scenes yet. Templates are scene-sized prose blocks the writer can use as a structural blueprint for new scenes." />
          ) : (
            snapshot.templateScenes.map((scene) => (
              <TemplateSceneRow
                key={scene.id}
                template={scene}
                onClick={() => onSelectTemplateScene(scene.id)}
              />
            ))
          )}
        </Section>
      </div>
    </div>
  );
}

function Header({
  snapshot,
  onOpenSuggestions,
  onOpenEntityProposals,
  onOpenRelationshipProposals,
}: {
  snapshot: BibleWorkspaceSnapshot;
  onOpenSuggestions: () => void;
  onOpenEntityProposals: () => void;
  onOpenRelationshipProposals: () => void;
}) {
  const pendingCount = snapshot.suggestions.length;
  const proposalsCount = (snapshot.proposedEntities ?? []).length;
  const relationshipProposalsCount = (snapshot.proposedRelationships ?? [])
    .length;
  const discoveringCount = (snapshot.discoveringSceneIds ?? []).length;
  return (
    <div className="flex items-baseline justify-between border-b border-loom-border px-6 py-4">
      <div>
        <h1 className="text-base font-medium text-loom-fg">
          {snapshot.projectTitle}
        </h1>
        <p className="mt-0.5 text-xs text-loom-fg-tertiary">
          {snapshot.scenes.length} scene
          {snapshot.scenes.length === 1 ? "" : "s"}
        </p>
      </div>
      <div className="flex gap-2">
        {discoveringCount > 0 && (
          <span
            className="inline-flex items-center gap-1.5 rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-1.5 text-xs font-medium text-amber-400"
            title="Entity discovery is running on at least one scene. Results land in the Entity proposals queue when complete (~30 s/scene)."
          >
            <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" />
            Discovering {discoveringCount} scene
            {discoveringCount === 1 ? "" : "s"}…
          </span>
        )}
        {proposalsCount > 0 && (
          <button
            type="button"
            onClick={onOpenEntityProposals}
            className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-3 py-1.5 text-xs font-medium text-emerald-400 hover:bg-emerald-500/20 focus:outline-none focus:ring-1 focus:ring-emerald-400"
          >
            {proposalsCount} entity proposal{proposalsCount === 1 ? "" : "s"} →
          </button>
        )}
        {relationshipProposalsCount > 0 && (
          <button
            type="button"
            onClick={onOpenRelationshipProposals}
            className="rounded-md border border-sky-500/40 bg-sky-500/10 px-3 py-1.5 text-xs font-medium text-sky-400 hover:bg-sky-500/20 focus:outline-none focus:ring-1 focus:ring-sky-400"
          >
            {relationshipProposalsCount} relationship proposal
            {relationshipProposalsCount === 1 ? "" : "s"} →
          </button>
        )}
        {pendingCount > 0 && (
          <button
            type="button"
            onClick={onOpenSuggestions}
            className="rounded-md border border-loom-accent/40 bg-loom-accent/10 px-3 py-1.5 text-xs font-medium text-loom-accent hover:bg-loom-accent/20 focus:outline-none focus:ring-1 focus:ring-loom-accent"
          >
            {pendingCount} pending suggestion{pendingCount === 1 ? "" : "s"} →
          </button>
        )}
      </div>
    </div>
  );
}

function Section({
  title,
  count,
  headerAction,
  children,
}: {
  title: string;
  count: number;
  headerAction?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="border-b border-loom-border last:border-b-0">
      <div className="flex items-baseline justify-between px-6 pt-4 pb-2">
        <h2 className="text-xs font-medium uppercase tracking-wider text-loom-fg-secondary">
          {title}
        </h2>
        <div className="flex items-baseline gap-3">
          {headerAction}
          <span className="text-xs text-loom-fg-tertiary">{count}</span>
        </div>
      </div>
      <div className="px-3 pb-3">{children}</div>
    </section>
  );
}

function CharacterRow({
  character,
  pendingSuggestions,
  onClick,
}: {
  character: Character;
  pendingSuggestions: PendingSuggestion[];
  onClick: () => void;
}) {
  const knownFactCount = Object.values(character.knownFactsBySceneId).reduce(
    (sum, facts) => sum + facts.length,
    0,
  );
  return (
    <button
      type="button"
      onClick={onClick}
      className="group block w-full cursor-pointer rounded-lg px-3 py-2.5 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-sm font-medium text-loom-fg">
          {character.name || "(unnamed)"}
        </span>
        <div className="flex shrink-0 items-baseline gap-2 text-[11px] text-loom-fg-tertiary">
          {character.role && (
            <span className="rounded bg-loom-bg-elevated px-1.5 py-0.5 text-loom-fg-secondary">
              {character.role}
            </span>
          )}
          {character.injectionMode === "keyed" && (
            <span className="text-loom-accent">keyed</span>
          )}
          {knownFactCount > 0 && (
            <span title={`${knownFactCount} accepted facts`}>
              {knownFactCount} fact{knownFactCount === 1 ? "" : "s"}
            </span>
          )}
          {pendingSuggestions.length > 0 && (
            <span className="text-loom-accent" title="Pending suggestions">
              {pendingSuggestions.length} pending
            </span>
          )}
        </div>
      </div>
      {character.description && (
        <p className="mt-1.5 line-clamp-2 text-xs leading-snug text-loom-fg-secondary">
          {character.description}
        </p>
      )}
    </button>
  );
}

function LorebookRow({
  entry,
  onClick,
}: {
  entry: LorebookEntry;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="group block w-full cursor-pointer rounded-lg px-3 py-2.5 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-sm font-medium text-loom-fg">
          {entry.name || "(unnamed entry)"}
        </span>
        <div className="flex shrink-0 items-baseline gap-2 text-[11px] text-loom-fg-tertiary">
          <span
            className={cn(
              "rounded px-1.5 py-0.5",
              entry.activationMode === "constant"
                ? "bg-loom-accent/15 text-loom-accent"
                : "bg-loom-bg-elevated text-loom-fg-secondary",
            )}
          >
            {entry.activationMode}
          </span>
          {entry.group && (
            <span title={`group: ${entry.group}`}>
              {entry.group}
              {entry.weight ? ` (w${entry.weight})` : ""}
            </span>
          )}
          {!entry.enabled && <span className="text-loom-fg-tertiary">off</span>}
        </div>
      </div>
      {entry.keys.length > 0 && (
        <p className="mt-1 text-[11px] text-loom-fg-tertiary">
          keys: {entry.keys.join(", ")}
        </p>
      )}
      {entry.content && (
        <p className="mt-1 line-clamp-2 text-xs leading-snug text-loom-fg-secondary">
          {entry.content}
        </p>
      )}
    </button>
  );
}

function ReferenceRow({
  reference,
  onClick,
}: {
  reference: SnapshotReference;
  onClick: () => void;
}) {
  const wordCount = reference.body
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
  const ingestState =
    reference.chunkCount === null
      ? { label: "not ingested", className: "text-loom-fg-tertiary" }
      : {
          label: `${reference.chunkCount} chunk${reference.chunkCount === 1 ? "" : "s"}`,
          className: "text-loom-accent",
        };
  return (
    <button
      type="button"
      onClick={onClick}
      className="group block w-full cursor-pointer rounded-lg px-3 py-2.5 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-sm font-medium text-loom-fg">
          {reference.name || "(unnamed reference)"}
        </span>
        <div className="flex shrink-0 items-baseline gap-2 text-[11px] text-loom-fg-tertiary">
          {reference.nsfw && (
            <span
              className="rounded bg-loom-bg-elevated px-1.5 py-0.5 text-loom-fg-secondary"
              title="Marked NSFW; retriever can be filtered on this flag."
            >
              nsfw
            </span>
          )}
          <span title="Word count of the reference body.">
            {wordCount} word{wordCount === 1 ? "" : "s"}
          </span>
          <span className={ingestState.className}>{ingestState.label}</span>
          {reference.dModelStale === true && (
            <span
              className="rounded bg-amber-500/15 px-1.5 py-0.5 font-medium text-amber-400"
              title="This reference was ingested under a different embedder model. Re-ingest to make its vectors compose correctly with the current retriever."
            >
              needs re-ingest
            </span>
          )}
        </div>
      </div>
      {reference.body && (
        <p className="mt-1 line-clamp-2 text-xs leading-snug text-loom-fg-secondary">
          {reference.body.trim().slice(0, 200)}
        </p>
      )}
    </button>
  );
}

function TemplateSceneRow({
  template,
  onClick,
}: {
  template: SnapshotTemplateScene;
  onClick: () => void;
}) {
  const wordCount = template.body
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
  const extractState =
    template.beatCount === null
      ? { label: "not extracted", className: "text-loom-fg-tertiary" }
      : {
          label: `${template.beatCount} beat${template.beatCount === 1 ? "" : "s"}`,
          className: "text-loom-accent",
        };
  return (
    <button
      type="button"
      onClick={onClick}
      className="group block w-full cursor-pointer rounded-lg px-3 py-2.5 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-sm font-medium text-loom-fg">
          {template.name || "(unnamed template)"}
        </span>
        <div className="flex shrink-0 items-baseline gap-2 text-[11px] text-loom-fg-tertiary">
          {template.nsfw && (
            <span
              className="rounded bg-loom-bg-elevated px-1.5 py-0.5 text-loom-fg-secondary"
              title="Marked NSFW."
            >
              nsfw
            </span>
          )}
          <span title="Word count of the template body.">
            {wordCount} word{wordCount === 1 ? "" : "s"}
          </span>
          <span className={extractState.className}>{extractState.label}</span>
        </div>
      </div>
      {template.body && (
        <p className="mt-1 line-clamp-2 text-xs leading-snug text-loom-fg-secondary">
          {template.body.trim().slice(0, 200)}
        </p>
      )}
    </button>
  );
}

function SceneExemplarRow({
  exemplar,
  onClick,
}: {
  exemplar: SnapshotSceneExemplar;
  onClick: () => void;
}) {
  const wordCount = exemplar.body
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
  // Two-flag status: chunks (retrieval) + beats (skeleton). Color
  // the badge by which sidecars are present.
  const chunkBadgeClass = exemplar.hasIndex
    ? "text-loom-accent"
    : "text-loom-fg-tertiary";
  const beatBadgeClass = exemplar.hasBeats
    ? "text-loom-accent"
    : "text-loom-fg-tertiary";
  const chunkLabel = exemplar.hasIndex
    ? `${exemplar.chunkCount ?? "?"} chunks`
    : "no chunks";
  const beatLabel = exemplar.hasBeats
    ? `${exemplar.beatCount ?? "?"} beats`
    : "no beats";
  return (
    <button
      type="button"
      onClick={onClick}
      className="group block w-full cursor-pointer rounded-lg px-3 py-2.5 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="truncate text-sm font-medium text-loom-fg">
          {exemplar.name || "(unnamed exemplar)"}
        </span>
        <div className="flex shrink-0 items-baseline gap-2 text-[11px] text-loom-fg-tertiary">
          {exemplar.nsfw && (
            <span
              className="rounded bg-loom-bg-elevated px-1.5 py-0.5 text-loom-fg-secondary"
              title="Marked NSFW."
            >
              nsfw
            </span>
          )}
          <span title="Word count of the exemplar body.">
            {wordCount} word{wordCount === 1 ? "" : "s"}
          </span>
          <span className={chunkBadgeClass}>{chunkLabel}</span>
          <span className={beatBadgeClass}>{beatLabel}</span>
        </div>
      </div>
      {exemplar.body && (
        <p className="mt-1 line-clamp-2 text-xs leading-snug text-loom-fg-secondary">
          {exemplar.body.trim().slice(0, 200)}
        </p>
      )}
    </button>
  );
}

function EmptyRow({ text }: { text: string }) {
  return (
    <div className="px-3 py-3 text-xs italic text-loom-fg-tertiary">{text}</div>
  );
}

// References + TemplateScenes are file-system entities — they can't
// be persisted while the project is in-memory (Untitled). Disable
// the corresponding Add buttons in that state with a tooltip rather
// than firing intents that no-op silently.
function AddButton({
  label,
  onClick,
  enabled,
  disabledHint,
}: {
  label: string;
  onClick: () => void;
  enabled: boolean;
  disabledHint: string;
}) {
  return (
    <button
      type="button"
      onClick={enabled ? onClick : undefined}
      disabled={!enabled}
      title={enabled ? undefined : disabledHint}
      className={cn(
        "text-xs",
        enabled
          ? "text-loom-accent hover:underline"
          : "cursor-not-allowed text-loom-fg-tertiary",
      )}
    >
      {label}
    </button>
  );
}
