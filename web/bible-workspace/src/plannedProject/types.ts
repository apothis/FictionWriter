// Types mirroring the Swift Codable shapes for the Planned Project
// wizard bridge. Keep in sync with:
//   - Sources/LoomCore/Models/PlannedProjectSnapshot.swift (snapshot)
//   - Sources/LoomCore/Models/Style.swift                  (Style)
//   - Sources/LoomCore/Models/PlannedProjectConfig.swift   (config)
//   - Sources/LoomCore/Generation/OutlineGeneration.swift  (GeneratedOutline)
// The wire format is the source of truth; this file is the JS mirror.

export type StyleType = "genre" | "register";

export interface Style {
  id: string;
  name: string;
  type: StyleType;
  descriptor: string;
  constraints: string[];
  exemplars: string[];
  isBuiltIn: boolean;
}

export interface SnapshotFramework {
  id: string;
  displayName: string;
}

export interface PlannedProjectSnapshot {
  styles: Style[];
  frameworks: SnapshotFramework[];
}

export type LengthScenario =
  | "flashFiction"
  | "shortStory"
  | "novelette"
  | "novella"
  | "novel";

export interface PlannedProjectConfig {
  premise: string;
  characterSketch: string;
  lengthScenario: LengthScenario;
  frameworkId: string;
  assignedStyleIds: string[];
}

// Outline shapes — loose where the wizard doesn't edit the field.
// Swift's decoders are forward-tolerant (decodeIfPresent + defaults),
// so round-tripping a partially-edited outline is safe.
export interface Scene {
  id: string;
  title: string;
  summary: string;
  status: string;
  targetWordCount?: number | null;
  [k: string]: unknown;
}

export interface Chapter {
  id: string;
  title: string;
  sceneIds: string[];
  summary?: string | null;
  targetWordCount?: number | null;
  [k: string]: unknown;
}

export interface Part {
  id: string;
  title: string;
  chapters: Chapter[];
  [k: string]: unknown;
}

export interface Manuscript {
  parts: Part[];
  orphanedSceneIds: string[];
  [k: string]: unknown;
}

export interface GeneratedOutline {
  manuscript: Manuscript;
  scenes: Scene[];
}
