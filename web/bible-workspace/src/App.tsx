import { useEffect, useState } from "react";
import type {
  BibleWorkspaceSnapshot,
  CharacterPatch,
  LorebookEntryPatch,
} from "./types";
import { postIntent, subscribeToSnapshots } from "./bridge";
import { EntityList } from "./views/EntityList";
import { CharacterEditor } from "./views/CharacterEditor";
import { LorebookEditor } from "./views/LorebookEditor";
import { SuggestionsQueue } from "./views/SuggestionsQueue";

// Top-level routing. Sessions 2-5 extended the Selection union as
// each editor surface landed. Session 5 adds a top-level
// `suggestions` kind for the cross-character pending-suggestions
// view — no id, since the surface lists all pending suggestions
// across the project.
type Selection =
  | { kind: "character"; id: string }
  | { kind: "lorebook"; id: string }
  | { kind: "suggestions" }
  | null;

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
    if (!character) return renderList();
    return (
      <CharacterEditor
        character={character}
        allCharacters={snapshot.characters}
        scenes={snapshot.scenes}
        dispatchPatch={(patch: CharacterPatch) =>
          postIntent({ kind: "patchCharacter", id: character.id, patch })
        }
        onDeleteFact={(sceneId: string, factId: string) =>
          postIntent({
            kind: "deleteKnownFact",
            characterId: character.id,
            sceneId,
            factId,
          })
        }
        onBack={() => setSelection(null)}
      />
    );
  }

  if (selection?.kind === "lorebook") {
    const entry = snapshot.lorebook.find((e) => e.id === selection.id);
    if (!entry) return renderList();
    return (
      <LorebookEditor
        entry={entry}
        dispatchPatch={(patch: LorebookEntryPatch) =>
          postIntent({ kind: "patchLorebookEntry", id: entry.id, patch })
        }
        onBack={() => setSelection(null)}
        onDelete={() => {
          postIntent({ kind: "deleteLorebookEntry", id: entry.id });
          setSelection(null);
        }}
      />
    );
  }

  if (selection?.kind === "suggestions") {
    return (
      <SuggestionsQueue
        suggestions={snapshot.suggestions}
        characters={snapshot.characters}
        scenes={snapshot.scenes}
        onAccept={(factId: string) => postIntent({ kind: "acceptSuggestion", factId })}
        onReject={(factId: string) => postIntent({ kind: "rejectSuggestion", factId })}
        onBack={() => setSelection(null)}
      />
    );
  }

  return renderList();

  function renderList() {
    return (
      <EntityList
        snapshot={snapshot!}
        onSelectCharacter={(id) => setSelection({ kind: "character", id })}
        onSelectLorebookEntry={(id) => setSelection({ kind: "lorebook", id })}
        onOpenSuggestions={() => setSelection({ kind: "suggestions" })}
        onAddLorebookEntry={() => {
          const name = `Entry ${snapshot!.lorebook.length + 1}`;
          postIntent({ kind: "addLorebookEntry", name });
        }}
      />
    );
  }
}
