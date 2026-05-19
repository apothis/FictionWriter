import type { ProjectToolsSnapshot } from "./types";

// Dev-only mock snapshots for `vite dev` browser preview. `tool` is
// taken from the URL hash (#antislop / #workframing); default framing.

export function devMockSnapshot(tool: string): ProjectToolsSnapshot {
  const base = {
    sceneId: null,
    sceneTitle: "",
    framing: "",
    antiSlopPhrases: [] as string[],
    projectTitle: "Dev Mock Project",
    sceneCharacters: [],
    undressedCharacterIds: [],
    workFraming: [],
  };

  if (tool.includes("antislop")) {
    return {
      ...base,
      tool: "antislop",
      antiSlopPhrases: [
        "shivers down her spine",
        "voice barely above a whisper",
        "a testament to",
        "her core",
      ],
    };
  }

  if (tool.includes("workframing")) {
    return {
      ...base,
      tool: "workframing",
      workFraming: [
        { name: "non-consent", stance: "playedStraight" },
        { name: "an unhappy ending", stance: "playedStraight" },
        { name: "graphic violence", stance: "critiqued" },
      ],
    };
  }

  return {
    ...base,
    tool: "framing",
    sceneId: "00000000-0000-0000-0000-0000000000F1",
    sceneTitle: "The Beach",
    framing:
      "Hate-sex dynamic between Chantal and Marek; neither will say it first. High tension, crude register.",
    sceneCharacters: [
      { id: "11111111-1111-1111-1111-111111111111", name: "Chantal" },
      { id: "33333333-3333-3333-3333-333333333333", name: "Marek" },
    ],
    undressedCharacterIds: ["11111111-1111-1111-1111-111111111111"],
  };
}
