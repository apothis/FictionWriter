import { useEffect, useState } from "react";
import type {
  BibleWorkspaceSnapshot,
  CharacterPatch,
  LorebookEntryPatch,
  ReferencePatch,
  SceneExemplarPatch,
  TemplateScenePatch,
} from "./types";
import { postIntent, subscribeToSnapshots } from "./bridge";
import { EntityList } from "./views/EntityList";
import { CharacterEditor } from "./views/CharacterEditor";
import { LorebookEditor } from "./views/LorebookEditor";
import { ReferenceEditor } from "./views/ReferenceEditor";
import { TemplateSceneEditor } from "./views/TemplateSceneEditor";
import { SceneExemplarEditor } from "./views/SceneExemplarEditor";
import { SuggestionsQueue } from "./views/SuggestionsQueue";
import { EntityProposalsQueue } from "./views/EntityProposalsQueue";
import { RelationshipProposalsQueue } from "./views/RelationshipProposalsQueue";

// Top-level routing. Sessions 2-5 extended the Selection union as
// each editor surface landed. Phase 5 production A2.2 added the
// `reference` kind; Phase 7.b.5 adds `template` for the Scene-
// Template Generation feature.
type Selection =
  | { kind: "character"; id: string }
  | { kind: "lorebook"; id: string }
  | { kind: "reference"; id: string }
  | { kind: "template"; id: string }
  | { kind: "sceneExemplar"; id: string }
  | { kind: "suggestions" }
  | { kind: "entityProposals" }
  | { kind: "relationshipProposals" }
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

  if (selection?.kind === "reference") {
    const reference = snapshot.references.find((r) => r.id === selection.id);
    if (!reference) return renderList();
    const isIngesting = (snapshot.ingestingReferenceIds ?? []).includes(
      reference.id,
    );
    return (
      <ReferenceEditor
        reference={reference}
        dispatchPatch={(patch: ReferencePatch) =>
          postIntent({ kind: "patchReference", id: reference.id, patch })
        }
        onBack={() => setSelection(null)}
        onDelete={() => {
          postIntent({ kind: "deleteReference", id: reference.id });
          setSelection(null);
        }}
        onIngest={() =>
          postIntent({ kind: "ingestReference", id: reference.id })
        }
        isIngesting={isIngesting}
      />
    );
  }

  if (selection?.kind === "template") {
    const template = snapshot.templateScenes.find((t) => t.id === selection.id);
    if (!template) return renderList();
    const isExtracting = (snapshot.extractingTemplateIds ?? []).includes(
      template.id,
    );
    return (
      <TemplateSceneEditor
        template={template}
        dispatchPatch={(patch: TemplateScenePatch) =>
          postIntent({ kind: "patchTemplateScene", id: template.id, patch })
        }
        onBack={() => setSelection(null)}
        onDelete={() => {
          postIntent({ kind: "deleteTemplateScene", id: template.id });
          setSelection(null);
        }}
        onExtract={() =>
          postIntent({ kind: "extractTemplateScene", id: template.id })
        }
        isExtracting={isExtracting}
      />
    );
  }

  if (selection?.kind === "sceneExemplar") {
    const exemplar = (snapshot.sceneExemplars ?? []).find(
      (e) => e.id === selection.id,
    );
    if (!exemplar) return renderList();
    // Phase 8.b.7 — in-flight is true while EITHER sub-pipeline is
    // pending for the shared UUID. One fan-out ingest action triggers
    // both sets simultaneously; the UI surfaces one unified state.
    const isIngesting =
      (snapshot.extractingTemplateIds ?? []).includes(exemplar.id) ||
      (snapshot.ingestingReferenceIds ?? []).includes(exemplar.id);
    return (
      <SceneExemplarEditor
        exemplar={exemplar}
        dispatchPatch={(patch: SceneExemplarPatch) =>
          postIntent({ kind: "patchSceneExemplar", id: exemplar.id, patch })
        }
        onBack={() => setSelection(null)}
        onDelete={() => {
          postIntent({ kind: "deleteSceneExemplar", id: exemplar.id });
          setSelection(null);
        }}
        onIngest={() =>
          postIntent({ kind: "ingestSceneExemplar", id: exemplar.id })
        }
        isIngesting={isIngesting}
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

  if (selection?.kind === "entityProposals") {
    return (
      <EntityProposalsQueue
        proposals={snapshot.proposedEntities ?? []}
        onAccept={(proposalId, accepted) =>
          postIntent({
            kind: "acceptEntityProposal",
            proposalId,
            accepted,
          })
        }
        onReject={(proposalId) =>
          postIntent({ kind: "rejectEntityProposal", proposalId })
        }
        onBack={() => setSelection(null)}
      />
    );
  }

  if (selection?.kind === "relationshipProposals") {
    return (
      <RelationshipProposalsQueue
        proposals={snapshot.proposedRelationships ?? []}
        onAccept={(proposalId, demoteConflicting) =>
          postIntent({
            kind: "acceptRelationshipProposal",
            proposalId,
            demoteConflicting,
          })
        }
        onReject={(proposalId) =>
          postIntent({ kind: "rejectRelationshipProposal", proposalId })
        }
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
        onSelectReference={(id) => setSelection({ kind: "reference", id })}
        onSelectTemplateScene={(id) => setSelection({ kind: "template", id })}
        onSelectSceneExemplar={(id) =>
          setSelection({ kind: "sceneExemplar", id })
        }
        onOpenSuggestions={() => setSelection({ kind: "suggestions" })}
        onOpenEntityProposals={() => setSelection({ kind: "entityProposals" })}
        onOpenRelationshipProposals={() =>
          setSelection({ kind: "relationshipProposals" })
        }
        onAddLorebookEntry={() => {
          const name = `Entry ${snapshot!.lorebook.length + 1}`;
          postIntent({ kind: "addLorebookEntry", name });
        }}
        onAddReference={() => {
          const name = `Reference ${snapshot!.references.length + 1}`;
          postIntent({ kind: "createReference", name });
        }}
        onAddTemplateScene={() => {
          const name = `Template ${snapshot!.templateScenes.length + 1}`;
          postIntent({ kind: "createTemplateScene", name });
        }}
        onAddSceneExemplar={() => {
          const count = (snapshot!.sceneExemplars ?? []).length + 1;
          const name = `Scene Exemplar ${count}`;
          // Empty body — user edits in the new editor pane and
          // hits Ingest to fire both sub-pipelines. Same lazy-init
          // pattern References + TemplateScenes use today.
          postIntent({
            kind: "createSceneExemplar",
            name,
            body: "",
            nsfw: false,
          });
        }}
      />
    );
  }
}
