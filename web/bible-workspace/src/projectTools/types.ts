// Mirrors ProjectToolsSnapshot.swift — the wire format for the
// project-tools webview bundle. Swift is the source of truth.

export interface ToolsCharacter {
  id: string;
  name: string;
}

export type ContentStance = "playedStraight" | "subverted" | "critiqued";

export interface FramedElement {
  name: string;
  stance: ContentStance;
}

export interface ProjectToolsSnapshot {
  tool: "framing" | "antislop" | "workframing";
  sceneId: string | null;
  sceneTitle: string;
  framing: string;
  antiSlopPhrases: string[];
  projectTitle: string;
  // Framing tool only — the cast, plus who's marked undressed.
  sceneCharacters: ToolsCharacter[];
  undressedCharacterIds: string[];
  // Work-framing tool only — framed content elements.
  workFraming: FramedElement[];
}
