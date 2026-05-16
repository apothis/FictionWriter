import { useEffect, useMemo, useState } from "react";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type Connection,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import type {
  Character,
  RelationshipMapPosition,
  SnapshotProposedRelationship,
} from "../types";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";

// Phase 10 follow-up — visual relationship mapper.
// Increment 4: pending relationship-discovery proposals render as
// dashed ghost edges; clicking one reviews + accepts/rejects it on
// the map, without a trip to the proposals queue.

interface Props {
  characters: Character[];
  layout: RelationshipMapPosition[];
  proposals: SnapshotProposedRelationship[];
  onEditCharacter: (id: string) => void;
  onMoveNode: (characterId: string, x: number, y: number) => void;
  onSetEdge: (
    fromId: string,
    toId: string,
    kind: string,
    status: "current" | "past",
    notes: string,
  ) => void;
  onDeleteEdge: (fromId: string, toId: string, kind: string) => void;
  onAcceptProposal: (proposalId: string, demoteConflicting: boolean) => void;
  onRejectProposal: (proposalId: string) => void;
  onBack: () => void;
}

interface EdgeDraft {
  fromId: string;
  toId: string;
  kind: string;
  status: "current" | "past";
  notes: string;
  originalKind: string | null;
}

interface EdgeData extends Record<string, unknown> {
  fromId?: string;
  toId?: string;
  kind?: string;
  status?: "current" | "past";
  notes?: string;
  // Present only on ghost (proposed) edges.
  proposal?: SnapshotProposedRelationship;
}

/// Match a discovery-proposal name (proposals are name-based) to a
/// bible character — canonical name or any alias, case-insensitive.
function resolveCharacterId(
  name: string,
  characters: Character[],
): string | null {
  const needle = name.trim().toLowerCase();
  if (!needle) return null;
  const hit = characters.find(
    (c) =>
      c.name.trim().toLowerCase() === needle ||
      c.aliases.some((a) => a.trim().toLowerCase() === needle),
  );
  return hit?.id ?? null;
}

function circleLayout(count: number): { x: number; y: number }[] {
  const radius = Math.max(180, count * 38);
  const cx = radius + 80;
  const cy = radius + 80;
  return Array.from({ length: count }, (_, i) => {
    const angle = (2 * Math.PI * i) / Math.max(1, count) - Math.PI / 2;
    return {
      x: cx + radius * Math.cos(angle),
      y: cy + radius * Math.sin(angle),
    };
  });
}

function buildNodes(
  characters: Character[],
  layout: RelationshipMapPosition[],
): Node[] {
  const saved = new Map(layout.map((p) => [p.characterId, p]));
  const fallback = circleLayout(characters.length);
  return characters.map((c, i) => {
    const savedPos = saved.get(c.id);
    return {
      id: c.id,
      position: savedPos ? { x: savedPos.x, y: savedPos.y } : fallback[i],
      data: { label: c.name || "(unnamed)" },
      type: "default",
      deletable: false,
    };
  });
}

function buildEdges(
  characters: Character[],
  proposals: SnapshotProposedRelationship[],
): Edge[] {
  const ids = new Set(characters.map((c) => c.id));
  const edges: Edge[] = [];
  // Real (accepted) edges.
  for (const c of characters) {
    c.relationships.forEach((rel, idx) => {
      if (rel.toCharacterId === c.id || !ids.has(rel.toCharacterId)) return;
      const status: "current" | "past" =
        rel.status === "past" ? "past" : "current";
      const past = status === "past";
      const data: EdgeData = {
        fromId: c.id,
        toId: rel.toCharacterId,
        kind: rel.kind,
        status,
        notes: rel.notes ?? "",
      };
      edges.push({
        id: `${c.id}:${idx}`,
        source: c.id,
        target: rel.toCharacterId,
        label: rel.kind,
        labelShowBg: true,
        deletable: false,
        data,
        style: past
          ? { stroke: "#6b7280", strokeDasharray: "5 5" }
          : { stroke: "#7c9cf5" },
        markerEnd: { type: "arrowclosed" as const },
      });
    });
  }
  // Ghost edges — pending discovery proposals, resolvable to two
  // distinct bible characters.
  for (const p of proposals) {
    const from = resolveCharacterId(p.fromName, characters);
    const to = resolveCharacterId(p.toName, characters);
    if (!from || !to || from === to) continue;
    edges.push({
      id: `proposal:${p.id}`,
      source: from,
      target: to,
      label: `${p.kind} (proposed)`,
      labelShowBg: true,
      deletable: false,
      animated: true,
      data: { proposal: p } as EdgeData,
      style: { stroke: "#d9a441", strokeDasharray: "6 4" },
      markerEnd: { type: "arrowclosed" as const },
    });
  }
  return edges;
}

export function RelationshipGraph({
  characters,
  layout,
  proposals,
  onEditCharacter,
  onMoveNode,
  onSetEdge,
  onDeleteEdge,
  onAcceptProposal,
  onRejectProposal,
  onBack,
}: Props) {
  const initialNodes = useMemo(
    () => buildNodes(characters, layout),
    [characters, layout],
  );
  const initialEdges = useMemo(
    () => buildEdges(characters, proposals),
    [characters, proposals],
  );
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
  const [editing, setEditing] = useState<EdgeDraft | null>(null);
  const [reviewing, setReviewing] =
    useState<SnapshotProposedRelationship | null>(null);

  // Re-sync from the snapshot when the bible or the proposal set
  // changes — the React Flow state hooks only seed once.
  useEffect(() => {
    setNodes(buildNodes(characters, layout));
  }, [characters, layout, setNodes]);
  useEffect(() => {
    setEdges(buildEdges(characters, proposals));
  }, [characters, proposals, setEdges]);

  function onConnect(conn: Connection) {
    if (!conn.source || !conn.target) return;
    setEditing({
      fromId: conn.source,
      toId: conn.target,
      kind: "",
      status: "current",
      notes: "",
      originalKind: null,
    });
  }

  function saveDraft(draft: EdgeDraft) {
    const kind = draft.kind.trim();
    if (!kind) return;
    if (draft.originalKind && draft.originalKind !== kind) {
      onDeleteEdge(draft.fromId, draft.toId, draft.originalKind);
    }
    onSetEdge(draft.fromId, draft.toId, kind, draft.status, draft.notes);
    setEditing(null);
  }

  function deleteDraft(draft: EdgeDraft) {
    if (draft.originalKind) {
      onDeleteEdge(draft.fromId, draft.toId, draft.originalKind);
    }
    setEditing(null);
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="text-sm font-medium text-loom-fg">
          Relationship map
        </span>
        <span className="text-xs text-loom-fg-tertiary">
          {characters.length} character{characters.length === 1 ? "" : "s"}
          {" · drag character→character to link · click an edge to edit"}
        </span>
      </header>
      <div className="min-h-0 flex-1">
        {characters.length < 2 ? (
          <EmptyState />
        ) : (
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onNodeDragStop={(_, node) =>
              onMoveNode(node.id, node.position.x, node.position.y)
            }
            onNodeDoubleClick={(_, node) => onEditCharacter(node.id)}
            onConnect={onConnect}
            onEdgeClick={(_, edge) => {
              const d = edge.data as EdgeData | undefined;
              if (!d) return;
              if (d.proposal) {
                setReviewing(d.proposal);
              } else if (d.fromId && d.toId && d.kind !== undefined) {
                setEditing({
                  fromId: d.fromId,
                  toId: d.toId,
                  kind: d.kind,
                  status: d.status ?? "current",
                  notes: d.notes ?? "",
                  originalKind: d.kind,
                });
              }
            }}
            deleteKeyCode={null}
            fitView
            proOptions={{ hideAttribution: true }}
          >
            <Background />
            <Controls />
            <MiniMap pannable zoomable />
          </ReactFlow>
        )}
      </div>
      {editing && (
        <EdgeEditor
          draft={editing}
          characters={characters}
          onSave={saveDraft}
          onDelete={deleteDraft}
          onCancel={() => setEditing(null)}
        />
      )}
      {reviewing && (
        <ProposalReview
          proposal={reviewing}
          onAccept={(demote) => {
            onAcceptProposal(reviewing.id, demote);
            setReviewing(null);
          }}
          onReject={() => {
            onRejectProposal(reviewing.id);
            setReviewing(null);
          }}
          onCancel={() => setReviewing(null)}
        />
      )}
    </div>
  );
}

function EdgeEditor({
  draft,
  characters,
  onSave,
  onDelete,
  onCancel,
}: {
  draft: EdgeDraft;
  characters: Character[];
  onSave: (d: EdgeDraft) => void;
  onDelete: (d: EdgeDraft) => void;
  onCancel: () => void;
}) {
  const [kind, setKind] = useState(draft.kind);
  const [status, setStatus] = useState<"current" | "past">(draft.status);
  const [notes, setNotes] = useState(draft.notes);

  const nameOf = (id: string) =>
    characters.find((c) => c.id === id)?.name || "(unnamed)";
  const isNew = draft.originalKind === null;

  return (
    <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/40">
      <div className="w-[22rem] rounded-lg border border-loom-border bg-loom-bg p-4 shadow-xl">
        <p className="mb-1 text-sm font-medium text-loom-fg">
          {isNew ? "New relationship" : "Edit relationship"}
        </p>
        <p className="mb-3 text-xs text-loom-fg-tertiary">
          {nameOf(draft.fromId)} → {nameOf(draft.toId)}
        </p>
        <label className="mb-1 block text-[11px] text-loom-fg-secondary">
          Kind (from {nameOf(draft.fromId)}’s point of view)
        </label>
        <Input
          value={kind}
          onChange={(e) => setKind(e.target.value)}
          placeholder="girlfriend, sister, rival…"
          autoFocus
        />
        <label className="mb-1 mt-3 block text-[11px] text-loom-fg-secondary">
          Status
        </label>
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value as "current" | "past")}
          className="w-full rounded border border-loom-border bg-loom-bg-input px-2 py-1 text-sm text-loom-fg"
        >
          <option value="current">current</option>
          <option value="past">past</option>
        </select>
        <label className="mb-1 mt-3 block text-[11px] text-loom-fg-secondary">
          Notes
        </label>
        <Textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={2}
        />
        <div className="mt-4 flex items-center justify-between">
          <div>
            {!isNew && (
              <Button variant="ghost" onClick={() => onDelete(draft)}>
                Delete
              </Button>
            )}
          </div>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
            <Button onClick={() => onSave({ ...draft, kind, status, notes })}>
              Save
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ProposalReview({
  proposal,
  onAccept,
  onReject,
  onCancel,
}: {
  proposal: SnapshotProposedRelationship;
  onAccept: (demoteConflicting: boolean) => void;
  onReject: () => void;
  onCancel: () => void;
}) {
  const conflicts = proposal.conflictsWithCurrent ?? [];
  return (
    <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/40">
      <div className="w-[24rem] rounded-lg border border-loom-border bg-loom-bg p-4 shadow-xl">
        <p className="mb-1 text-sm font-medium text-loom-fg">
          Proposed relationship
        </p>
        <p className="mb-3 text-xs text-loom-fg-tertiary">
          Discovered in “{proposal.sourceSceneTitle}”
        </p>
        <p className="text-sm text-loom-fg">
          {proposal.fromName} →{" "}
          <span className="font-medium text-loom-accent">{proposal.kind}</span>{" "}
          → {proposal.toName}
          <span className="ml-2 text-[11px] text-loom-fg-tertiary">
            ({proposal.status})
          </span>
        </p>
        {proposal.evidenceQuote && (
          <p className="mt-2 border-l-2 border-loom-border pl-2 text-xs italic text-loom-fg-secondary">
            “{proposal.evidenceQuote}”
          </p>
        )}
        {conflicts.length > 0 && (
          <p className="mt-3 rounded bg-loom-bg-input p-2 text-[11px] text-loom-fg-secondary">
            Accepting marks {proposal.fromName}’s current relationship
            {conflicts.length === 1 ? "" : "s"} with {conflicts.join(", ")} as
            past.
          </p>
        )}
        <div className="mt-4 flex items-center justify-between">
          <Button variant="ghost" onClick={onReject}>
            Reject
          </Button>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
            <Button onClick={() => onAccept(conflicts.length > 0)}>
              Accept
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="rounded-lg border border-dashed border-loom-border p-6 text-center text-xs text-loom-fg-tertiary">
        <p className="mb-2 text-sm text-loom-fg-secondary">
          Need at least two characters to map relationships.
        </p>
        <p>Add characters in the bible, then return here.</p>
      </div>
    </div>
  );
}
