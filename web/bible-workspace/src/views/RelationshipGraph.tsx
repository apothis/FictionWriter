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
import type { Character, RelationshipMapPosition } from "../types";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";

// Phase 10 follow-up — visual relationship mapper. Characters are
// draggable nodes; each Character.relationships entry is a directed,
// labelled edge. Increment 3: in-graph edge editing — drag node→node
// to create an edge, click an edge to edit kind/status/notes or
// delete it.

interface Props {
  characters: Character[];
  layout: RelationshipMapPosition[];
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
  onBack: () => void;
}

/// A draft passed to the edge editor. `originalKind === null` means a
/// brand-new edge being drawn; otherwise it's the kind the existing
/// edge had on open (used to remove the old slot if the kind changes).
interface EdgeDraft {
  fromId: string;
  toId: string;
  kind: string;
  status: "current" | "past";
  notes: string;
  originalKind: string | null;
}

interface EdgeData extends Record<string, unknown> {
  fromId: string;
  toId: string;
  kind: string;
  status: "current" | "past";
  notes: string;
}

/// Initial node placement — an even circle. Used only for characters
/// without a saved position.
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

function buildEdges(characters: Character[]): Edge[] {
  const ids = new Set(characters.map((c) => c.id));
  const edges: Edge[] = [];
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
  return edges;
}

export function RelationshipGraph({
  characters,
  layout,
  onEditCharacter,
  onMoveNode,
  onSetEdge,
  onDeleteEdge,
  onBack,
}: Props) {
  const initialNodes = useMemo(
    () => buildNodes(characters, layout),
    [characters, layout],
  );
  const initialEdges = useMemo(() => buildEdges(characters), [characters]);
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
  const [editing, setEditing] = useState<EdgeDraft | null>(null);

  // Re-sync from the snapshot when the bible changes — `useNodesState`
  // / `useEdgesState` only seed from their initial value, so an edge
  // edit (which re-pushes a snapshot) would otherwise not show until
  // remount. Node positions survive because `buildNodes` reads the
  // persisted layout.
  useEffect(() => {
    setNodes(buildNodes(characters, layout));
  }, [characters, layout, setNodes]);
  useEffect(() => {
    setEdges(buildEdges(characters));
  }, [characters, setEdges]);

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
    // Editing with a changed kind: the (to, kind) slot moved, so drop
    // the old slot before writing the new one.
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
              setEditing({
                fromId: d.fromId,
                toId: d.toId,
                kind: d.kind,
                status: d.status,
                notes: d.notes,
                originalKind: d.kind,
              });
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
              <Button
                variant="ghost"
                onClick={() => onDelete(draft)}
              >
                Delete
              </Button>
            )}
          </div>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
            <Button
              onClick={() =>
                onSave({ ...draft, kind, status, notes })
              }
            >
              Save
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
