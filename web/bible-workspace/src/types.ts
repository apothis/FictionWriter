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
  // Phase 8.c — Wegmann re-ingest UX. true → vectors were embedded
  // under a different model than the current default; UI shows a
  // "needs re-ingest" badge. false → fresh. null → no info (either
  // not yet ingested, or no current embedder configured).
  // Optional for legacy-payload tolerance.
  dModelStale?: boolean | null;
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

// Phase 8.b.6 — bridge projection of the unified Scene Exemplar.
// Joins a Reference + Template by shared UUID; `hasIndex` /
// `hasBeats` indicate which sidecars are on disk. The single
// "Ingest" affordance fans out to both Phase 5 chunking+embed AND
// Phase 7 Pass-A extraction.
export interface SnapshotSceneExemplar {
  id: string;
  name: string;
  nsfw: boolean;
  body: string;
  hasIndex: boolean;
  hasBeats: boolean;
  chunkCount: number | null;
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
  // Phase 8.b.6 — unified scene-exemplar list. Optional for legacy-
  // payload tolerance; readers default to [].
  sceneExemplars?: SnapshotSceneExemplar[];
  // False for "Untitled" in-memory projects with no on-disk URL.
  // References + TemplateScenes are file-system entities that can't
  // be persisted until the project is saved; UI disables the Add
  // buttons when this is false. Optional in the type to tolerate
  // pre-field snapshots; readers should default to true.
  isProjectOnDisk?: boolean;
  // Templates whose Pass-A extraction is currently in flight on the
  // Swift side. Uppercase UUID strings. The template editor flips
  // its Extract button to "Extracting…" when its id appears here.
  // Optional for legacy-payload tolerance — default to [].
  extractingTemplateIds?: string[];
  // Phase 8.b.7 — References whose chunk+embed pipeline is in flight.
  // Same wire format + semantics as extractingTemplateIds. The
  // unified Scene Exemplar editor reads BOTH and flips its Ingest
  // button to "Ingesting…" when its id appears in either.
  ingestingReferenceIds?: string[];
  // Phase 9 — scenes whose entity-discovery pipeline is currently in
  // flight. Same wire format as extractingTemplateIds. The EntityList
  // header surfaces a "Discovering N scene(s)…" indicator while non-
  // empty so the user knows results are coming.
  discoveringSceneIds?: string[];
  // Phase 9 entity-discovery — pending proposals from the discovery
  // pipeline (Tools/EntityDiscoverySpike output, eventually editor-
  // triggered live discovery). EntityProposalsQueue.tsx renders this
  // list; accept/reject route through the bridge to AppState.
  // Optional for legacy-payload tolerance — default to [].
  proposedEntities?: SnapshotProposedEntity[];
}

// Phase 9 entity-discovery — webview projection of a ProposedEntity.
// `kind` is "character" | "place"; `sourceSceneTitle` is pre-resolved
// at snapshot-build time so the view doesn't have to cross-reference
// `scenes[]` for every row. `attachedFacts` embedded inline so the
// row card can expand without a second bridge call.
export interface SnapshotProposedEntity {
  id: string;
  // "object" landed as the Phase 9 v2 extension (named significant
  // artefacts — Excalibur, The Necronomicon).
  kind: "character" | "place" | "object";
  canonicalName: string;
  aliases: string[];
  oneLine: string;
  evidenceQuote: string;
  sourceSceneId: string;
  sourceSceneTitle: string;
  confidence: number;
  attachedFacts: SnapshotProposedFact[];
}

export interface SnapshotProposedFact {
  fact: string;
  certainty: string;
  evidenceQuote: string;
}

// Payload accompanying acceptEntityProposal — what the user
// committed to (may differ from the LLM's original proposal if
// they edited the form fields).
export interface ProposedEntityAcceptance {
  canonicalName: string;
  aliases: string[];
  oneLine: string;
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

// Mirrors SceneExemplarPatch.swift — identical shape to ReferencePatch.
// The Swift handler applies the patch to BOTH the underlying
// Reference and Template under the shared UUID so the projection
// stays in lockstep.
export interface SceneExemplarPatch {
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
