import { useEffect, useState } from "react";
import type { Character, DynamicSheet, DynamicSheetPatch } from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";
import { Section, Field } from "../components/EditorLayout";

// P2b — Dynamic Sheet editor. A structured per-relationship spec
// (roles / wants / soft+hard limits / safeword / arc) fed to the
// writer model. Mirrors LorebookEditor: local draft + debounced
// dispatch; reset effect keyed on sheet.id.

interface Props {
  sheet: DynamicSheet;
  characters: Character[];
  dispatchPatch: (patch: DynamicSheetPatch) => void;
  onBack: () => void;
  onDelete: () => void;
}

export function DynamicSheetEditor({
  sheet,
  characters,
  dispatchPatch,
  onBack,
  onDelete,
}: Props) {
  const [draft, setDraft] = useState<DynamicSheet>(sheet);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(sheet);
  }, [sheet.id]);

  const send = useDebouncedCallback(
    (patch: DynamicSheetPatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof DynamicSheet>(field: K, value: DynamicSheet[K]) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    send({ [field]: value as never } as DynamicSheetPatch);
  }

  function toggleParticipant(id: string) {
    const next = draft.participantIds.includes(id)
      ? draft.participantIds.filter((p) => p !== id)
      : [...draft.participantIds, id];
    update("participantIds", next);
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed dynamic)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
        <Button variant="destructive" onClick={onDelete}>
          Delete dynamic
        </Button>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="e.g. Mira & Cole"
            />
          </Field>
          <Field
            label="Enabled"
            hint="Disabling skips this dynamic without removing it."
          >
            <label className="inline-flex items-center gap-2 text-sm text-loom-fg">
              <input
                type="checkbox"
                checked={draft.enabled}
                onChange={(e) => update("enabled", e.target.checked)}
              />
              <span>enabled</span>
            </label>
          </Field>
          <Field
            label="Always on"
            hint="On: injected into every generation. Off: injected only when a participant appears in the recent prose."
          >
            <label className="inline-flex items-center gap-2 text-sm text-loom-fg">
              <input
                type="checkbox"
                checked={draft.alwaysOn}
                onChange={(e) => update("alwaysOn", e.target.checked)}
              />
              <span>always on</span>
            </label>
          </Field>
          <Field
            label="Participants"
            hint="Characters in this dynamic. Drives keyed activation when 'always on' is off."
          >
            {characters.length === 0 ? (
              <p className="text-[11px] text-loom-fg-tertiary">
                No characters in the bible yet.
              </p>
            ) : (
              <div className="space-y-1">
                {characters.map((c) => (
                  <label
                    key={c.id}
                    className="flex items-center gap-2 text-sm text-loom-fg"
                  >
                    <input
                      type="checkbox"
                      checked={draft.participantIds.includes(c.id)}
                      onChange={() => toggleParticipant(c.id)}
                    />
                    <span>{c.name || "(unnamed)"}</span>
                  </label>
                ))}
              </div>
            )}
          </Field>
        </Section>

        <Section
          title="The dynamic"
          hint="A spec the writer model treats as a positive constraint — what the dynamic is, never a prohibition list. Empty fields are omitted from the prompt."
        >
          <Field label="Roles" hint="Each party's role in the dynamic.">
            <Textarea
              rows={3}
              value={draft.roles}
              onChange={(e) => update("roles", e.target.value)}
            />
          </Field>
          <Field label="Wants" hint="What each party wants from it.">
            <Textarea
              rows={3}
              value={draft.wants}
              onChange={(e) => update("wants", e.target.value)}
            />
          </Field>
          <Field label="Soft limits" hint="Conditional — negotiable in context.">
            <Textarea
              rows={2}
              value={draft.softLimits}
              onChange={(e) => update("softLimits", e.target.value)}
            />
          </Field>
          <Field label="Hard limits" hint="Never — the dynamic does not cross these.">
            <Textarea
              rows={2}
              value={draft.hardLimits}
              onChange={(e) => update("hardLimits", e.target.value)}
            />
          </Field>
          <Field label="Safeword" hint="The in-world safeword or stop convention.">
            <Input
              value={draft.safeword}
              onChange={(e) => update("safeword", e.target.value)}
            />
          </Field>
          <Field label="Arc" hint="Where the dynamic starts versus where it ends.">
            <Textarea
              rows={3}
              value={draft.arc}
              onChange={(e) => update("arc", e.target.value)}
            />
          </Field>
        </Section>
      </div>
    </div>
  );
}
