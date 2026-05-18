import type {
  BibleWorkspaceSnapshot,
  Character,
  Relationship,
} from "./types";

// Dev-only mock snapshot. In `vite dev` (browser preview) there is no
// Swift host to call `window.loom.applySnapshot`, so the webview would
// sit forever on "Awaiting first snapshot…". bridge.ts feeds this in
// when it detects no Swift host AND import.meta.env.DEV — so it never
// reaches the production bundle. It exercises the relationship mapper
// (a character web + two pending proposals); other views render from
// the same characters/empty lists.

function character(
  id: string,
  name: string,
  relationships: Relationship[],
): Character {
  return {
    id,
    name,
    aliases: [],
    role: "",
    oneLine: "",
    description: "",
    personality: "",
    appearance: "",
    voice: "",
    goals: "",
    relationships,
    avatarPath: null,
    canonBrief: null,
    customFields: [],
    injectionMode: "constant",
    knownFactsBySceneId: {},
  };
}

const CHANTAL = "11111111-1111-1111-1111-111111111111";
const MURIEL = "22222222-2222-2222-2222-222222222222";
const MAREK = "33333333-3333-3333-3333-333333333333";
const YELENA = "44444444-4444-4444-4444-444444444444";
const ANDERS = "55555555-5555-5555-5555-555555555555";
const SCENE = "99999999-9999-9999-9999-999999999999";

export const devMockSnapshot: BibleWorkspaceSnapshot = {
  projectTitle: "Dev Mock Project",
  characters: [
    character(CHANTAL, "Chantal", [
      { toCharacterId: MURIEL, kind: "girlfriend", status: "current", notes: "" },
      { toCharacterId: ANDERS, kind: "ex-boyfriend", status: "past", notes: "" },
    ]),
    character(MURIEL, "Muriel", [
      { toCharacterId: CHANTAL, kind: "girlfriend", status: "current", notes: "" },
    ]),
    character(MAREK, "Marek", [
      { toCharacterId: YELENA, kind: "rival", status: "current", notes: "" },
    ]),
    character(YELENA, "Yelena", []),
    character(ANDERS, "Anders", []),
  ],
  lorebook: [
    {
      id: "00000000-0000-0000-0000-0000000000E1",
      name: "The traitor reveal",
      content: "Marek has been feeding the rival crew their movements.",
      activationMode: "constant",
      keys: [],
      secondaryKeys: [],
      enabled: true,
      priority: 0,
      positionMode: "top",
      depth: null,
      maxRecentScenesScanned: 3,
      group: null,
      weight: null,
      sticky: false,
      activateFromSceneId: null,
      activateUntilSceneId: null,
    },
  ],
  dynamics: [
    {
      id: "00000000-0000-0000-0000-0000000000D1",
      name: "Chantal & Marek",
      participantIds: [CHANTAL, MAREK],
      roles: "Chantal sets the pace; Marek follows her lead.",
      wants: "Both want the power gap spoken aloud.",
      softLimits: "Nothing in front of the others.",
      hardLimits: "No lasting marks.",
      safeword: '"harbour"',
      arc: "Starts as a dare; becomes the spine of the relationship.",
      alwaysOn: true,
      enabled: true,
    },
  ],
  scenes: [{ id: SCENE, title: "The Beach" }],
  suggestions: [],
  references: [],
  templateScenes: [],
  sceneExemplars: [],
  isProjectOnDisk: true,
  proposedEntities: [],
  proposedRelationships: [
    {
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      fromName: "Yelena",
      toName: "Marek",
      kind: "ally",
      status: "current",
      evidenceQuote: "Yelena watched from the balcony, ready to help.",
      sourceSceneId: SCENE,
      sourceSceneTitle: "The Beach",
      conflictsWithCurrent: [],
    },
    {
      id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      fromName: "Anders",
      toName: "Muriel",
      kind: "close friend",
      status: "current",
      evidenceQuote: "Anders had known Muriel since university.",
      sourceSceneId: SCENE,
      sourceSceneTitle: "The Beach",
      conflictsWithCurrent: [],
    },
  ],
  relationshipMapLayout: [],
};
