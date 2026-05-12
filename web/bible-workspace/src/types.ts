// Types mirroring the Swift Codable shapes pushed over the
// WKScriptMessageHandler bridge. Keep these in sync with
// Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift — the wire
// format is the source of truth; this file is the JS-side mirror.
//
// Discrepancies will surface as JSON decoding errors on the Swift
// side (intent path, Session 2+) or as undefined-field access on
// the JS side (snapshot rendering, Session 1).

// Mirrors Loom's Character.swift — only the fields the workspace
// renders are typed strictly; everything else is loose so future
// Swift schema additions don't break the build before the TS
// mirror catches up.
export interface Character {
  id: string;
  name: string;
  aliases: string[];
  role: string;
  oneLine: string;
  description: string;
  personality: string;
  appearance: string;
  voice: string;
  goals: string;
  relationships: Relationship[];
  avatarPath: string | null;
  canonBrief: string | null;
  customFields: CharacterCustomField[];
  injectionMode: "constant" | "keyed";
  knownFactsBySceneId: Record<string, KnownFact[]>;
}

export interface Relationship {
  toCharacterId: string;
  kind: string;
  notes: string;
}

export interface CharacterCustomField {
  label: string;
  value: string;
  kind: string;
}

export interface KnownFact {
  id: string;
  fact: string;
  sourceSceneId: string | null;
  certainty: "asserted" | "suspected" | "unknown" | "mistaken";
  addedAt: string;
}

export interface LorebookEntry {
  id: string;
  name: string;
  content: string;
  activationMode: "constant" | "keyed" | "vectorised";
  keys: string[];
  secondaryKeys: string[];
  enabled: boolean;
  priority: number;
  positionMode: "top" | "bottom" | "depthN";
  depth: number | null;
  maxRecentScenesScanned: number;
  group: string | null;
  weight: number | null;
  sticky: boolean;
}

export interface SceneSummary {
  id: string;
  title: string;
}

export interface PendingSuggestion {
  factId: string;
  characterId: string;
  factText: string;
  certainty: string;
  evidenceQuote: string;
  sourceSceneId: string | null;
}

export interface BibleWorkspaceSnapshot {
  projectTitle: string;
  characters: Character[];
  lorebook: LorebookEntry[];
  scenes: SceneSummary[];
  suggestions: PendingSuggestion[];
}

// Mirrors CharacterPatch.swift — every field optional. The React
// editor sends only the fields that diverged from the snapshot,
// keeping intent payloads small and the diff explicit.
//
// Collection semantics:
// - undefined: leave the array unchanged
// - []: clear it
// - [x, y]: replace entirely
export interface CharacterPatch {
  name?: string;
  aliases?: string[];
  role?: string;
  oneLine?: string;
  description?: string;
  personality?: string;
  appearance?: string;
  voice?: string;
  goals?: string;
  relationships?: Relationship[];
  canonBrief?: string;
  customFields?: CharacterCustomField[];
  injectionMode?: "constant" | "keyed";
}
