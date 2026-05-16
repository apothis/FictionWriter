import { useState } from "react";
import type { SnapshotProposedRelationship } from "../types";
import { Button } from "../components/ui/Button";
import { cn } from "../lib/cn";

// Phase 10 Part B/3 — accept/reject review for relationship-discovery
// proposals. Sibling of EntityProposalsQueue: header with count +
// back, flat scrollable list of cards, accept/reject per row.
//
// Difference vs entity proposals: a relationship row isn't editable
// here (the N×N matrix grid owns editing). And accepting a proposal
// whose `conflictsWithCurrent` is non-empty opens a demote-confirm
// dialog — the from-character already has a current romantic partner,
// and the user decides whether the prior one flips to `.past`.

interface Props {
  proposals: SnapshotProposedRelationship[];
  onAccept: (proposalId: string, demoteConflicting: boolean) => void;
  onReject: (proposalId: string) => void;
  onBack: () => void;
}

export function RelationshipProposalsQueue({
  proposals,
  onAccept,
  onReject,
  onBack,
}: Props) {
  // The proposal awaiting a demote decision, or null. Lifted to the
  // queue level so the modal overlays the whole list.
  const [confirmFor, setConfirmFor] =
    useState<SnapshotProposedRelationship | null>(null);

  const handleAccept = (p: SnapshotProposedRelationship) => {
    if ((p.conflictsWithCurrent ?? []).length > 0) {
      setConfirmFor(p);
    } else {
      onAccept(p.id, false);
    }
  };

  return (
    <div className="relative flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="text-sm font-medium text-loom-fg">
          Relationship proposals
        </span>
        <span className="text-xs text-loom-fg-tertiary">
          {proposals.length} pending
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
                onAccept={() => handleAccept(p)}
                onReject={() => onReject(p.id)}
              />
            ))}
          </ul>
        )}
      </div>
      {confirmFor && (
        <DemoteConfirmDialog
          proposal={confirmFor}
          onResolve={(demote) => {
            onAccept(confirmFor.id, demote);
            setConfirmFor(null);
          }}
          onCancel={() => setConfirmFor(null)}
        />
      )}
    </div>
  );
}

function ProposalRow({
  proposal,
  onAccept,
  onReject,
}: {
  proposal: SnapshotProposedRelationship;
  onAccept: () => void;
  onReject: () => void;
}) {
  return (
    <li className="rounded-lg border border-loom-border bg-loom-bg-elevated p-4">
      <div className="flex items-baseline justify-between gap-3">
        <div className="flex min-w-0 flex-wrap items-baseline gap-2">
          <span className="text-sm font-medium text-loom-fg">
            {proposal.fromName}
          </span>
          <span className="text-xs text-loom-fg-tertiary">→</span>
          <span className="rounded bg-loom-bg-input px-1.5 py-0.5 text-xs text-loom-fg-secondary">
            {proposal.kind}
          </span>
          <span className="text-xs text-loom-fg-tertiary">→</span>
          <span className="text-sm font-medium text-loom-fg">
            {proposal.toName}
          </span>
          <StatusPill status={proposal.status} />
        </div>
        <div className="flex shrink-0 gap-2">
          <Button onClick={onAccept}>Accept</Button>
          <Button variant="ghost" onClick={onReject}>
            Reject
          </Button>
        </div>
      </div>

      <p className="mt-2 text-[11px] text-loom-fg-tertiary">
        from{" "}
        <span className="text-loom-fg-secondary">
          {proposal.sourceSceneTitle}
        </span>
      </p>

      {proposal.evidenceQuote && (
        <blockquote className="mt-2 border-l-2 border-loom-border pl-3 text-xs italic leading-snug text-loom-fg-secondary">
          “{proposal.evidenceQuote}”
        </blockquote>
      )}

      {(proposal.conflictsWithCurrent ?? []).length > 0 && (
        <p className="mt-2 text-[11px] text-amber-400">
          ⚠ {proposal.fromName} already has a current partner (
          {(proposal.conflictsWithCurrent ?? []).join(", ")}) — accepting
          will ask whether to demote it.
        </p>
      )}
    </li>
  );
}

function StatusPill({ status }: { status: "current" | "past" }) {
  return (
    <span
      className={cn(
        "rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider",
        status === "current"
          ? "bg-loom-accent/15 text-loom-accent"
          : "bg-loom-bg-input text-loom-fg-tertiary",
      )}
    >
      {status}
    </span>
  );
}

function DemoteConfirmDialog({
  proposal,
  onResolve,
  onCancel,
}: {
  proposal: SnapshotProposedRelationship;
  onResolve: (demoteConflicting: boolean) => void;
  onCancel: () => void;
}) {
  const conflicts = proposal.conflictsWithCurrent ?? [];
  return (
    <div className="absolute inset-0 flex items-center justify-center bg-black/50 p-6">
      <div className="w-full max-w-md rounded-lg border border-loom-border bg-loom-bg-elevated p-5 shadow-xl">
        <h2 className="text-sm font-medium text-loom-fg">
          Demote prior partner?
        </h2>
        <p className="mt-2 text-xs leading-snug text-loom-fg-secondary">
          {proposal.fromName} already has a current{" "}
          {conflicts.length === 1 ? "partner" : "partners"}:{" "}
          <span className="text-loom-fg">{conflicts.join(", ")}</span>.
          Accepting “{proposal.kind}” with {proposal.toName} adds a second
          current romantic relationship.
        </p>
        <p className="mt-2 text-xs leading-snug text-loom-fg-tertiary">
          Demoting flips the prior relationship to “past” — it is kept, not
          deleted.
        </p>
        <div className="mt-4 flex justify-end gap-2">
          <Button variant="ghost" onClick={onCancel}>
            Cancel
          </Button>
          <Button onClick={() => onResolve(false)}>Keep both current</Button>
          <Button variant="destructive" onClick={() => onResolve(true)}>
            Demote prior to past
          </Button>
        </div>
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="rounded-lg border border-dashed border-loom-border p-6 text-center text-xs text-loom-fg-tertiary">
      <p className="mb-2 text-sm text-loom-fg-secondary">
        No pending relationship proposals.
      </p>
      <p>
        Proposals arrive here when relationship discovery runs against a
        scene — use the Bible menu’s “Discover Relationships in Current
        Scene”.
      </p>
    </div>
  );
}
