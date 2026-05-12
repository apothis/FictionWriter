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

// Top-level routing — extended in Session 3 with a `lorebook`
// selection kind. The selection shape keeps the same pattern as
// `character` so future entity types (factions, timeline events,
// style sheets — per LOOM_BIBLE_WORKSPACE.md §3 future-proofing)
// slot in cleanly.
type Selection =
  | { kind: "character"; id: string }
  | { kind: "lorebook"; id: string }
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
    if (!character) {
      // Stale selection (character deleted out of band) — fall back
      // to the list rather than rendering a stale empty form.
      return renderList();
    }
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
    if (!entry) {
      return renderList();
    }
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

  return renderList();

  function renderList() {
    return (
      <EntityList
        snapshot={snapshot!}
        onSelectCharacter={(id) => setSelection({ kind: "character", id })}
        onSelectLorebookEntry={(id) => setSelection({ kind: "lorebook", id })}
        onAddLorebookEntry={() => {
          // Match AppKit inspector's pattern: create with a sequential
          // default name, user renames in the editor. Skips
          // window.prompt (which silently no-ops in WKWebView
          // without a WKUIDelegate) — better UX anyway, no modal
          // interruption.
          const name = `Entry ${snapshot!.lorebook.length + 1}`;
          postIntent({ kind: "addLorebookEntry", name });
        }}
      />
    );
  }
}
