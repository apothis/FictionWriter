import type {
  BibleWorkspaceSnapshot,
  Character,
  LorebookEntry,
  PendingSuggestion,
} from "../types";
import { cn } from "../lib/cn";

// Session 1: read-only entity list rendering. Characters + lorebook
// + a summary strip showing scene count and pending-suggestion
// count. No editing affordances — those land in Sessions 2-5.

interface Props {
  snapshot: BibleWorkspaceSnapshot;
  onSelectCharacter: (id: string) => void;
  onSelectLorebookEntry: (id: string) => void;
  onAddLorebookEntry: () => void;
}

export function EntityList({
  snapshot,
  onSelectCharacter,
  onSelectLorebookEntry,
  onAddLorebookEntry,
}: Props) {
  return (
    <div className="flex h-full flex-col">
      <Header snapshot={snapshot} />
      <div className="flex-1 overflow-auto">
        <Section title="Characters" count={snapshot.characters.length}>
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
      </div>
    </div>
  );
}

function Header({ snapshot }: { snapshot: BibleWorkspaceSnapshot }) {
  return (
    <div className="flex items-baseline justify-between border-b border-loom-border px-6 py-4">
      <div>
        <h1 className="text-base font-medium text-loom-fg">
          {snapshot.projectTitle}
        </h1>
        <p className="mt-0.5 text-xs text-loom-fg-tertiary">
          {snapshot.scenes.length} scene
          {snapshot.scenes.length === 1 ? "" : "s"}
          {snapshot.suggestions.length > 0 && (
            <> · {snapshot.suggestions.length} pending suggestion
              {snapshot.suggestions.length === 1 ? "" : "s"}
            </>
          )}
        </p>
      </div>
      <span className="text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
        Read-only · Session 1
      </span>
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

function EmptyRow({ text }: { text: string }) {
  return (
    <div className="px-3 py-3 text-xs italic text-loom-fg-tertiary">{text}</div>
  );
}
