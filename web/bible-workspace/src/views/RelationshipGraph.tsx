import { useMemo } from "react";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import type { Character } from "../types";
import { Button } from "../components/ui/Button";

// Phase 10 follow-up — visual relationship mapper. Characters are
// draggable nodes; each Character.relationships entry is a directed,
// labelled edge. Current vs past edges are styled distinctly.
// Increment 1: read-only render + drag/zoom/pan. Layout persistence
// and in-graph edge editing land in later increments.

interface Props {
  characters: Character[];
  onEditCharacter: (id: string) => void;
  onBack: () => void;
}

/// Initial node placement — an even circle. Persisted layout
/// (a later increment) will override this.
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

function buildNodes(characters: Character[]): Node[] {
  const positions = circleLayout(characters.length);
  return characters.map((c, i) => ({
    id: c.id,
    position: positions[i],
    data: { label: c.name || "(unnamed)" },
    type: "default",
  }));
}

function buildEdges(characters: Character[]): Edge[] {
  const ids = new Set(characters.map((c) => c.id));
  const edges: Edge[] = [];
  for (const c of characters) {
    c.relationships.forEach((rel, idx) => {
      // Skip self-loops and edges to characters not in the bible.
      if (rel.toCharacterId === c.id || !ids.has(rel.toCharacterId)) return;
      const past = rel.status === "past";
      edges.push({
        id: `${c.id}:${idx}`,
        source: c.id,
        target: rel.toCharacterId,
        label: rel.kind,
        labelShowBg: true,
        animated: false,
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
  onEditCharacter,
  onBack,
}: Props) {
  const initialNodes = useMemo(() => buildNodes(characters), [characters]);
  const initialEdges = useMemo(() => buildEdges(characters), [characters]);
  const [nodes, , onNodesChange] = useNodesState(initialNodes);
  const [edges, , onEdgesChange] = useEdgesState(initialEdges);

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
          {" · double-click a character to edit"}
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
            onNodeDoubleClick={(_, node) => onEditCharacter(node.id)}
            nodesConnectable={false}
            fitView
            proOptions={{ hideAttribution: true }}
          >
            <Background />
            <Controls />
            <MiniMap pannable zoomable />
          </ReactFlow>
        )}
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
