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

// Phase 5 production A2.1 — bridge projection of `ReferenceText`.
// `chunkCount: null` = no `.index` sidecar on disk yet (UI surfaces
// an "Ingest" prompt); non-null = vectors are present (count shown
// inline). `body` is the editable prose blob.
export interface SnapshotReference {
  id: string;
  name: string;
  nsfw: boolean;
  createdAt: string;
  body: string;
  chunkCount: number | null;
}

// Phase 7.b.5 — bridge projection of `TemplateScene`. Mirrors
// `SnapshotReference` shape exactly. `beatCount: null` = no
// `.beats.json` sidecar yet (UI surfaces an "Extract" prompt);
// non-null = the skeleton is on disk and ready for use as the
// structural blueprint in `.generateFromTemplate` mode.
export interface SnapshotTemplateScene {
  id: string;
  name: string;
  nsfw: boolean;
  createdAt: string;
  body: string;
  beatCount: number | null;
}

export interface BibleWorkspaceSnapshot {
  projectTitle: string;
  characters: Character[];
  lorebook: LorebookEntry[];
  scenes: SceneSummary[];
  suggestions: PendingSuggestion[];
  references: SnapshotReference[];
  templateScenes: SnapshotTemplateScene[];
  // False for "Untitled" in-memory projects with no on-disk URL.
  // References + TemplateScenes are file-system entities that can't
  // be persisted until the project is saved; UI disables the Add
  // buttons when this is false. Optional in the type to tolerate
  // pre-field snapshots; readers should default to true.
  isProjectOnDisk?: boolean;
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

// Mirrors ReferencePatch.swift — name / nsfw / body are user-editable.
// `id` is carried at the intent envelope; createdAt / extraFrontmatter
// are not patchable from the workspace.
export interface ReferencePatch {
  name?: string;
  nsfw?: boolean;
  body?: string;
}

// Mirrors TemplateScenePatch.swift — identical shape to ReferencePatch.
// Phase 7.b.5.
export interface TemplateScenePatch {
  name?: string;
  nsfw?: boolean;
  body?: string;
}

// Mirrors LorebookEntryPatch.swift — every field optional. Same
// semantics as CharacterPatch: undefined = leave alone, array = replace.
export interface LorebookEntryPatch {
  name?: string;
  content?: string;
  activationMode?: "constant" | "keyed" | "vectorised";
  keys?: string[];
  secondaryKeys?: string[];
  enabled?: boolean;
  priority?: number;
  positionMode?: "top" | "bottom" | "depthN";
  depth?: number;
  maxRecentScenesScanned?: number;
  group?: string;
  weight?: number;
  sticky?: boolean;
}
