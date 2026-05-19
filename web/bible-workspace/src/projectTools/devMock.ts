import type { ProjectToolsSnapshot } from "./types";

// Dev-only mock snapshots for `vite dev` browser preview.

export function devMockSnapshot(antislop: boolean): ProjectToolsSnapshot {
  if (antislop) {
    return {
      tool: "antislop",
      sceneId: null,
      sceneTitle: "",
      framing: "",
      antiSlopPhrases: [
        "shivers down her spine",
        "voice barely above a whisper",
        "a testament to",
        "her core",
      ],
      projectTitle: "Dev Mock Project",
      sceneCharacters: [],
      undressedCharacterIds: [],
    };
  }
  return {
    tool: "framing",
    sceneId: "00000000-0000-0000-0000-0000000000F1",
    sceneTitle: "The Beach",
    framing:
      "Hate-sex dynamic between Chantal and Marek; neither will say it first. High tension, crude register.",
    antiSlopPhrases: [],
    projectTitle: "Dev Mock Project",
    sceneCharacters: [
      { id: "11111111-1111-1111-1111-111111111111", name: "Chantal" },
      { id: "33333333-3333-3333-3333-333333333333", name: "Marek" },
    ],
    undressedCharacterIds: ["11111111-1111-1111-1111-111111111111"],
  };
}
