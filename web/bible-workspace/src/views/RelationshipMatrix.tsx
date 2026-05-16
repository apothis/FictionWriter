import type { Character, Relationship } from "../types";
import { Button } from "../components/ui/Button";
import { cn } from "../lib/cn";

// Phase 10 Part B/4 — N×N relationship matrix. Rows are the "from"
// character, columns the "to" character; each cell shows the directed
// relationship(s) the row character holds toward the column one
// (Character.relationships filtered by toCharacterId). Current and
// past edges are styled distinctly. Clicking any non-diagonal cell
// opens the row character's editor — that's where edges are added or
// changed.

interface Props {
  characters: Character[];
  onEditCharacter: (id: string) => void;
  onBack: () => void;
}

export function RelationshipMatrix({
  characters,
  onEditCharacter,
  onBack,
}: Props) {
  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="text-sm font-medium text-loom-fg">
          Relationship matrix
        </span>
        <span className="text-xs text-loom-fg-tertiary">
          {characters.length} character{characters.length === 1 ? "" : "s"}
        </span>
      </header>
      <div className="flex-1 overflow-auto p-6">
        {characters.length < 2 ? (
          <EmptyState />
        ) : (
          <>
            <p className="mb-3 text-xs text-loom-fg-tertiary">
              Each cell reads “row → column”. Click a cell to edit the row
              character.
            </p>
            <Matrix characters={characters} onEditCharacter={onEditCharacter} />
          </>
        )}
      </div>
    </div>
  );
}

function Matrix({
  characters,
  onEditCharacter,
}: {
  characters: Character[];
  onEditCharacter: (id: string) => void;
}) {
  const nameById = new Map(characters.map((c) => [c.id, c.name]));
  return (
    <table className="border-collapse">
      <thead>
        <tr>
          <th className="sticky left-0 z-10 bg-loom-bg p-2" />
          {characters.map((col) => (
            <th
              key={col.id}
              className="min-w-[7rem] border-b border-loom-border p-2 text-left text-[11px] font-medium text-loom-fg-secondary"
            >
              {col.name || "(unnamed)"}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {characters.map((row) => (
          <tr key={row.id}>
            <th className="sticky left-0 z-10 whitespace-nowrap border-r border-loom-border bg-loom-bg p-2 text-left text-[11px] font-medium text-loom-fg-secondary">
              {row.name || "(unnamed)"}
            </th>
            {characters.map((col) => (
              <Cell
                key={col.id}
                isSelf={row.id === col.id}
                edges={row.relationships.filter(
                  (r) => r.toCharacterId === col.id,
                )}
                fallbackName={(id) => nameById.get(id) ?? "(unknown)"}
                onClick={() => onEditCharacter(row.id)}
              />
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Cell({
  isSelf,
  edges,
  fallbackName,
  onClick,
}: {
  isSelf: boolean;
  edges: Relationship[];
  fallbackName: (id: string) => string;
  onClick: () => void;
}) {
  if (isSelf) {
    return (
      <td className="border-b border-loom-border bg-loom-bg-elevated/40 p-2 text-center text-loom-fg-tertiary">
        —
      </td>
    );
  }
  return (
    <td className="border-b border-loom-border p-1 align-top">
      <button
        type="button"
        onClick={onClick}
        className="block h-full min-h-[2.5rem] w-full rounded px-1.5 py-1 text-left hover:bg-loom-bg-elevated focus:bg-loom-bg-elevated focus:outline-none focus:ring-1 focus:ring-loom-accent"
      >
        {edges.length === 0 ? (
          <span className="text-[11px] text-loom-fg-tertiary/50">·</span>
        ) : (
          <div className="flex flex-wrap gap-1">
            {edges.map((e, i) => (
              <EdgePill key={i} edge={e} fallbackName={fallbackName} />
            ))}
          </div>
        )}
      </button>
    </td>
  );
}

function EdgePill({
  edge,
  fallbackName,
}: {
  edge: Relationship;
  fallbackName: (id: string) => string;
}) {
  const past = edge.status === "past";
  return (
    <span
      title={`${edge.kind} (${edge.status})${edge.notes ? ` — ${edge.notes}` : ""}`}
      className={cn(
        "rounded px-1.5 py-0.5 text-[10px] font-medium",
        past
          ? "bg-loom-bg-input text-loom-fg-tertiary line-through"
          : "bg-loom-accent/15 text-loom-accent",
      )}
    >
      {edge.kind || fallbackName(edge.toCharacterId)}
    </span>
  );
}

function EmptyState() {
  return (
    <div className="rounded-lg border border-dashed border-loom-border p-6 text-center text-xs text-loom-fg-tertiary">
      <p className="mb-2 text-sm text-loom-fg-secondary">
        Need at least two characters for a relationship matrix.
      </p>
      <p>Add characters in the bible, then return here.</p>
    </div>
  );
}
