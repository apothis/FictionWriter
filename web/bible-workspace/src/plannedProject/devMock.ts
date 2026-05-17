import type {
  GeneratedOutline,
  PlannedProjectConfig,
  PlannedProjectSnapshot,
  Scene,
} from "./types";

// Dev-only mock data. In `vite dev` (browser preview) there is no
// Swift host, so the wizard would have no style library and no way to
// resolve generate/create requests. bridge.ts feeds this in under
// `import.meta.env.DEV` only — it never reaches the production bundle.

function style(
  id: string,
  name: string,
  type: "genre" | "register",
  descriptor: string,
): PlannedProjectSnapshot["styles"][number] {
  return { id, name, type, descriptor, constraints: [], exemplars: [], isBuiltIn: true };
}

export const devMockSnapshot: PlannedProjectSnapshot = {
  styles: [
    style("11111111-1111-1111-1111-111111111111", "Noir", "genre",
      "Hard-boiled crime. Moral ambiguity, rain-slicked streets, cynical narration."),
    style("22222222-2222-2222-2222-222222222222", "Cozy Fantasy", "genre",
      "Low-stakes warmth in a magical setting. Found family, small triumphs."),
    style("33333333-3333-3333-3333-333333333333", "Space Opera", "genre",
      "Grand-scale science fiction. Star-spanning conflict, larger-than-life figures."),
    style("44444444-4444-4444-4444-444444444444", "Literary", "register",
      "Measured, interior prose. Precision of image over plot velocity."),
    style("55555555-5555-5555-5555-555555555555", "Terse", "register",
      "Short sentences. Concrete nouns. No throat-clearing."),
    style("66666666-6666-6666-6666-666666666666", "Lush", "register",
      "Sensory, rhythmic prose with room to breathe. Vivid but disciplined."),
  ],
  frameworks: [{ id: "save-the-cat", displayName: "Save the Cat" }],
};

function mockScene(n: number, title: string, summary: string): Scene {
  return {
    id: `dev-scene-${n}-${Math.random().toString(36).slice(2, 8)}`,
    title,
    summary,
    status: "todo",
    targetWordCount: 1500,
  };
}

function mockOutline(config: PlannedProjectConfig): GeneratedOutline {
  const flat = config.lengthScenario === "flashFiction" || config.lengthScenario === "shortStory";
  const scenes: Scene[] = [
    mockScene(1, "Opening Image", "The protagonist's ordinary world, before the disruption."),
    mockScene(2, "Catalyst", "An event upends the status quo and forces a choice."),
    mockScene(3, "Midpoint", "A false victory or false defeat raises the stakes."),
    mockScene(4, "All Is Lost", "The lowest point — the original plan has failed."),
    mockScene(5, "Finale", "The protagonist acts on what they have learned."),
  ];
  if (flat) {
    return {
      manuscript: { parts: [], orphanedSceneIds: scenes.map((s) => s.id) },
      scenes,
    };
  }
  const chapters = [
    {
      id: "dev-ch-1",
      title: "Chapter 1",
      sceneIds: scenes.slice(0, 3).map((s) => s.id),
      summary: "Setup and the inciting turn.",
      targetWordCount: 4500,
    },
    {
      id: "dev-ch-2",
      title: "Chapter 2",
      sceneIds: scenes.slice(3).map((s) => s.id),
      summary: "Collapse and resolution.",
      targetWordCount: 3000,
    },
  ];
  return {
    manuscript: {
      parts: [{ id: "dev-part-1", title: "Manuscript", chapters }],
      orphanedSceneIds: [],
    },
    scenes,
  };
}

/// Resolve a wizard request/reply intent in browser-preview mode.
export function devResolveRequest(
  kind: string,
  payload: Record<string, unknown>,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    if (kind === "generateOutline") {
      const config = payload.config as PlannedProjectConfig;
      setTimeout(() => resolve(mockOutline(config)), 1200);
    } else if (kind === "createPlannedProject") {
      setTimeout(() => resolve(undefined), 600);
    } else {
      reject(new Error(`[loom-wizard] devMock: unknown request kind ${kind}`));
    }
  });
}
