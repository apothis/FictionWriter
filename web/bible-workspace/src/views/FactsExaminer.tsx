import type { Character, KnownFact, SceneSummary } from "../types";
import { Button } from "../components/ui/Button";
import { cn } from "../lib/cn";

// Phase 4.5 Session 4 — accepted-facts examiner. Closes the §15.9
// audit gap: facts accepted from the suggestions queue used to
// disappear into `Character.knownFactsBySceneId` with no way to
// view or remove them. This view groups them by source scene and
// surfaces a per-fact delete button that dispatches
// `deleteKnownFact` intents.
//
// Empty buckets are filtered out — Swift's removeKnownFact mutator
// already cleans them up after a delete, so the dict only carries
// non-empty groups, but defending against stale data anyway.

interface FactWithScene {
  sceneId: string;
  sceneTitle: string;
  facts: KnownFact[];
}

interface Props {
  character: Character;
  scenes: SceneSummary[];
  onDeleteFact: (sceneId: string, factId: string) => void;
}

export function FactsExaminer({ character, scenes, onDeleteFact }: Props) {
  const sceneById = new Map(scenes.map((s) => [s.id, s.title]));

  // Group by sceneId in manuscript order (scenes[] is already in
  // canonical order from the snapshot builder). Scenes without
  // any facts are skipped; facts attached to a stale sceneId
  // surface under "(orphaned scene)" so the user can clean them up.
  const groups: FactWithScene[] = [];
  for (const scene of scenes) {
    const bucket = character.knownFactsBySceneId[scene.id] ?? [];
    if (bucket.length > 0) {
      groups.push({ sceneId: scene.id, sceneTitle: scene.title, facts: bucket });
    }
  }
  for (const [sceneId, bucket] of Object.entries(character.knownFactsBySceneId)) {
    if (!sceneById.has(sceneId) && bucket.length > 0) {
      groups.push({
        sceneId,
        sceneTitle: "(orphaned scene)",
        facts: bucket,
      });
    }
  }

  const totalCount = groups.reduce((sum, g) => sum + g.facts.length, 0);

  if (totalCount === 0) {
    return (
      <div className="rounded-lg border border-dashed border-loom-border p-6 text-center text-xs text-loom-fg-tertiary">
        <p className="mb-2 text-sm text-loom-fg-secondary">
          {character.name || "This character"} has no accepted facts yet.
        </p>
        <p>
          Facts arrive here when you accept ledger suggestions from the
          Bible inspector. Each accepted fact is anchored to the scene
          it was extracted from.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {groups.map((group) => (
        <div key={group.sceneId}>
          <h3 className="mb-2 text-xs font-medium uppercase tracking-wider text-loom-fg-secondary">
            {group.sceneTitle}
            <span className="ml-2 text-loom-fg-tertiary">
              {group.facts.length} fact{group.facts.length === 1 ? "" : "s"}
            </span>
          </h3>
          <ul className="space-y-2">
            {group.facts.map((fact) => (
              <FactRow
                key={fact.id}
                fact={fact}
                onDelete={() => onDeleteFact(group.sceneId, fact.id)}
              />
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function FactRow({ fact, onDelete }: { fact: KnownFact; onDelete: () => void }) {
  return (
    <li className="flex items-start gap-3 rounded-lg border border-loom-border bg-loom-bg-elevated p-3">
      <CertaintyPill certainty={fact.certainty} />
      <p className="flex-1 text-sm leading-snug text-loom-fg">{fact.fact}</p>
      <Button
        variant="ghost"
        onClick={onDelete}
        aria-label="Delete fact"
        className="shrink-0"
      >
        ✕
      </Button>
    </li>
  );
}

function CertaintyPill({ certainty }: { certainty: KnownFact["certainty"] }) {
  const styles: Record<KnownFact["certainty"], string> = {
    asserted: "bg-loom-accent/15 text-loom-accent",
    suspected: "bg-amber-500/15 text-amber-400",
    unknown: "bg-loom-bg-input text-loom-fg-tertiary",
    mistaken: "bg-red-500/15 text-red-400",
  };
  return (
    <span
      className={cn(
        "mt-0.5 inline-block shrink-0 rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider",
        styles[certainty] ?? styles.unknown,
      )}
    >
      {certainty}
    </span>
  );
}
