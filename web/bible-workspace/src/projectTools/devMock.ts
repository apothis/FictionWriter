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
  };
}
