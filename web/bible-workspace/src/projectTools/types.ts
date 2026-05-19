// Mirrors ProjectToolsSnapshot.swift — the wire format for the
// project-tools webview bundle. Swift is the source of truth.

export interface ToolsCharacter {
  id: string;
  name: string;
}

export interface ProjectToolsSnapshot {
  tool: "framing" | "antislop";
  sceneId: string | null;
  sceneTitle: string;
  framing: string;
  antiSlopPhrases: string[];
  projectTitle: string;
  // Framing tool only — the cast, plus who's marked undressed.
  sceneCharacters: ToolsCharacter[];
  undressedCharacterIds: string[];
}
