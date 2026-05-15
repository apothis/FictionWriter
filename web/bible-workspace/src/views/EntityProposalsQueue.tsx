import { useState } from "react";
import type {
  SnapshotProposedEntity,
  ProposedEntityAcceptance,
} from "../types";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { cn } from "../lib/cn";

// Phase 9 entity-discovery — accept/reject/edit review for the
// Tools/EntityDiscoverySpike output (later: live editor-triggered
// discovery). Mirrors the SuggestionsQueue.tsx pattern: header with
// count + back, flat scrollable list of cards, accept/reject per
// row. Difference vs Suggestions: each card has editable canonical
// name + aliases + one-line before commit — the user may want to
// tweak the LLM's name proposal before promoting to a real bible
// row.

interface Props {
  proposals: SnapshotProposedEntity[];
  onAccept: (proposalId: string, accepted: ProposedEntityAcceptance) => void;
  onReject: (proposalId: string) => void;
  onBack: () => void;
}

export function EntityProposalsQueue({
  proposals,
  onAccept,
  onReject,
  onBack,
}: Props) {
  const characterCount = proposals.filter((p) => p.kind === "character").length;
  const placeCount = proposals.filter((p) => p.kind === "place").length;

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="text-sm font-medium text-loom-fg">
          Entity proposals
        </span>
        <span className="text-xs text-loom-fg-tertiary">
          {proposals.length} pending ({characterCount} character
          {characterCount === 1 ? "" : "s"}, {placeCount} place
          {placeCount === 1 ? "" : "s"})
        </span>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        {proposals.length === 0 ? (
          <EmptyState />
        ) : (
          <ul className="space-y-3">
            {proposals.map((p) => (
              <ProposalRow
                key={p.id}
                proposal={p}
                onAccept={(accepted) => onAccept(p.id, accepted)}
                onReject={() => onReject(p.id)}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function ProposalRow({
  proposal,
  onAccept,
  onReject,
}: {
  proposal: SnapshotProposedEntity;
  onAccept: (accepted: ProposedEntityAcceptance) => void;
  onReject: () => void;
}) {
  // Local editable form state — pre-populated with the LLM's
  // proposed values. User can tweak before clicking Accept.
  const [canonicalName, setCanonicalName] = useState(proposal.canonicalName);
  const [aliasesText, setAliasesText] = useState(proposal.aliases.join(", "));
  const [oneLine, setOneLine] = useState(proposal.oneLine);
  const [expanded, setExpanded] = useState(false);

  const handleAccept = () => {
    const aliases = aliasesText
      .split(",")
      .map((a) => a.trim())
      .filter((a) => a.length > 0);
    onAccept({
      canonicalName: canonicalName.trim(),
      aliases,
      oneLine: oneLine.trim(),
    });
  };

  return (
    <li className="rounded-lg border border-loom-border bg-loom-bg-elevated p-4">
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <div className="flex items-baseline gap-2">
          <KindBadge kind={proposal.kind} />
          <span className="text-[11px] text-loom-fg-tertiary">
            from{" "}
            <span className="text-loom-fg-secondary">
              {proposal.sourceSceneTitle}
            </span>
          </span>
        </div>
        <div className="flex shrink-0 gap-2">
          <Button onClick={handleAccept}>Accept</Button>
          <Button variant="ghost" onClick={onReject}>
            Reject
          </Button>
        </div>
      </div>

      <div className="space-y-2">
        <div>
          <label className="mb-0.5 block text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
            Canonical name
          </label>
          <Input
            value={canonicalName}
            onChange={(e) => setCanonicalName(e.target.value)}
          />
        </div>
        <div>
          <label className="mb-0.5 block text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
            Aliases (comma-separated)
          </label>
          <Input
            value={aliasesText}
            onChange={(e) => setAliasesText(e.target.value)}
          />
        </div>
        <div>
          <label className="mb-0.5 block text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
            One-line
          </label>
          <Textarea
            value={oneLine}
            onChange={(e) => setOneLine(e.target.value)}
            rows={2}
          />
        </div>
      </div>

      {proposal.evidenceQuote && (
        <blockquote className="mt-3 border-l-2 border-loom-border pl-3 text-xs italic leading-snug text-loom-fg-secondary">
          “{proposal.evidenceQuote}”
        </blockquote>
      )}

      {proposal.attachedFacts.length > 0 && (
        <div className="mt-3">
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="text-[11px] text-loom-fg-tertiary hover:text-loom-fg"
          >
            {expanded ? "▼" : "▶"} {proposal.attachedFacts.length} attached fact
            {proposal.attachedFacts.length === 1 ? "" : "s"} (will be saved on
            accept)
          </button>
          {expanded && (
            <ul className="mt-2 space-y-1.5 pl-3">
              {proposal.attachedFacts.map((f, i) => (
                <li
                  key={i}
                  className="text-xs leading-snug text-loom-fg-secondary"
                >
                  <CertaintyPill certainty={f.certainty} /> {f.fact}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </li>
  );
}

function KindBadge({ kind }: { kind: "character" | "place" }) {
  const styles =
    kind === "character"
      ? "bg-loom-accent/15 text-loom-accent"
      : "bg-emerald-500/15 text-emerald-400";
  return (
    <span
      className={cn(
        "rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider",
        styles,
      )}
    >
      {kind}
    </span>
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
        "mr-1 inline-block rounded px-1 py-0.5 text-[9px] font-medium uppercase tracking-wider",
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
        No pending entity proposals.
      </p>
      <p>
        Proposals arrive here when the entity-discovery pipeline runs
        against a scene. Run{" "}
        <code className="rounded bg-loom-bg-input px-1 py-0.5">
          swift run EntityDiscoverySpike
        </code>{" "}
        with{" "}
        <code className="rounded bg-loom-bg-input px-1 py-0.5">
          --into &lt;project&gt;
        </code>{" "}
        to populate this queue from the spike output.
      </p>
    </div>
  );
}
