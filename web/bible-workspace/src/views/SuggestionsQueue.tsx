import type { Character, PendingSuggestion, SceneSummary } from "../types";
import { Button } from "../components/ui/Button";
import { cn } from "../lib/cn";

// Phase 4.5 Session 5 — cross-character pending-suggestions
// review. Flattened from the per-character chip in the side-pane
// inspector. Each row exposes the character, source scene, fact
// text, certainty + evidence quote, and inline accept/reject
// buttons; both dispatch intents that mutate the queue through
// AppState's existing API and re-trigger a snapshot push.

interface Props {
  suggestions: PendingSuggestion[];
  characters: Character[];
  scenes: SceneSummary[];
  onAccept: (factId: string) => void;
  onReject: (factId: string) => void;
  onBack: () => void;
}

export function SuggestionsQueue({
  suggestions,
  characters,
  scenes,
  onAccept,
  onReject,
  onBack,
}: Props) {
  const characterById = new Map(characters.map((c) => [c.id, c]));
  const sceneTitleById = new Map(scenes.map((s) => [s.id, s.title]));

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="text-sm font-medium text-loom-fg">
          Pending suggestions
        </span>
        <span className="text-xs text-loom-fg-tertiary">
          {suggestions.length} across {countDistinctCharacters(suggestions)} character
          {countDistinctCharacters(suggestions) === 1 ? "" : "s"}
        </span>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        {suggestions.length === 0 ? (
          <EmptyState />
        ) : (
          <ul className="space-y-3">
            {suggestions.map((suggestion) => (
              <SuggestionRow
                key={suggestion.factId}
                suggestion={suggestion}
                characterName={
                  characterById.get(suggestion.characterId)?.name ?? "(unknown character)"
                }
                sceneTitle={
                  suggestion.sourceSceneId
                    ? sceneTitleById.get(suggestion.sourceSceneId) ?? "(orphaned scene)"
                    : null
                }
                onAccept={() => onAccept(suggestion.factId)}
                onReject={() => onReject(suggestion.factId)}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function countDistinctCharacters(suggestions: PendingSuggestion[]): number {
  const ids = new Set<string>();
  for (const s of suggestions) ids.add(s.characterId);
  return ids.size;
}

function SuggestionRow({
  suggestion,
  characterName,
  sceneTitle,
  onAccept,
  onReject,
}: {
  suggestion: PendingSuggestion;
  characterName: string;
  sceneTitle: string | null;
  onAccept: () => void;
  onReject: () => void;
}) {
  return (
    <li className="rounded-lg border border-loom-border bg-loom-bg-elevated p-4">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <div className="flex items-baseline gap-2">
          <span className="rounded bg-loom-bg-input px-2 py-0.5 text-xs font-medium text-loom-fg">
            {characterName}
          </span>
          <CertaintyPill certainty={suggestion.certainty} />
          {sceneTitle && (
            <span className="text-[11px] text-loom-fg-tertiary">
              from <span className="text-loom-fg-secondary">{sceneTitle}</span>
            </span>
          )}
        </div>
        <div className="flex shrink-0 gap-2">
          <Button onClick={onAccept}>Accept</Button>
          <Button variant="ghost" onClick={onReject}>
            Reject
          </Button>
        </div>
      </div>
      <p className="text-sm leading-snug text-loom-fg">{suggestion.factText}</p>
      {suggestion.evidenceQuote && (
        <blockquote className="mt-2 border-l-2 border-loom-border pl-3 text-xs italic leading-snug text-loom-fg-secondary">
          “{suggestion.evidenceQuote}”
        </blockquote>
      )}
    </li>
  );
}

function CertaintyPill({ certainty }: { certainty: string }) {
  const styles: Record<string, string> = {
    asserted: "bg-loom-accent/15 text-loom-accent",
    suspected: "bg-amber-500/15 text-amber-400",
    unknown: "bg-loom-bg-input text-loom-fg-tertiary",
    mistaken: "bg-red-500/15 text-red-400",
  };
  return (
    <span
      className={cn(
        "rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider",
        styles[certainty] ?? styles.unknown,
      )}
    >
      {certainty}
    </span>
  );
}

function EmptyState() {
  return (
    <div className="rounded-lg border border-dashed border-loom-border p-6 text-center text-xs text-loom-fg-tertiary">
      <p className="mb-2 text-sm text-loom-fg-secondary">
        No pending suggestions.
      </p>
      <p>
        Suggestions arrive here after the ledger extractor processes a
        scene. Edit a scene in the main window and wait ~30s for new
        facts to land here.
      </p>
    </div>
  );
}
