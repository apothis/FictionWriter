import { useEffect, useState } from "react";
import type { BibleWorkspaceSnapshot, CharacterPatch } from "./types";
import { postIntent, subscribeToSnapshots } from "./bridge";
import { EntityList } from "./views/EntityList";
import { CharacterEditor } from "./views/CharacterEditor";

// Top-level routing — Session 1 had only the entity list. Session
// 2 adds a CharacterEditor view selected by clicking a character
// row. Sessions 3-5 will add Lorebook / Facts / Suggestions
// editors with the same pattern.
type Selection = { kind: "character"; id: string } | null;

export function App() {
  const [snapshot, setSnapshot] = useState<BibleWorkspaceSnapshot | null>(null);
  const [selection, setSelection] = useState<Selection>(null);

  useEffect(() => {
    return subscribeToSnapshots(setSnapshot);
  }, []);

  if (!snapshot) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-loom-fg-tertiary">
        Awaiting first snapshot from Loom…
      </div>
    );
  }

  if (selection?.kind === "character") {
    const character = snapshot.characters.find((c) => c.id === selection.id);
    if (!character) {
      // The selected character was deleted out of band — fall back
      // to the list rather than rendering a stale empty form.
      return (
        <EntityList
          snapshot={snapshot}
          onSelectCharacter={(id) => setSelection({ kind: "character", id })}
        />
      );
    }
    return (
      <CharacterEditor
        character={character}
        allCharacters={snapshot.characters}
        dispatchPatch={(patch: CharacterPatch) =>
          postIntent({ kind: "patchCharacter", id: character.id, patch })
        }
        onBack={() => setSelection(null)}
      />
    );
  }

  return (
    <EntityList
      snapshot={snapshot}
      onSelectCharacter={(id) => setSelection({ kind: "character", id })}
    />
  );
}
