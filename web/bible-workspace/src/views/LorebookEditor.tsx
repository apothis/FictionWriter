import { useEffect, useState } from "react";
import type { LorebookEntry, LorebookEntryPatch } from "../types";
import { Input } from "../components/ui/Input";
import { NumericField } from "../components/ui/NumericField";
import { Textarea } from "../components/ui/Textarea";
import { Select } from "../components/ui/Select";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";
import { Section, Field } from "../components/EditorLayout";

// Phase 4.5 Session 3 — full lorebook entry editor. All 11
// `LorebookEntry` fields (current v1 inspector surfaces only 4).
// Mirrors the CharacterEditor structure: local draft + debounced
// dispatch; reset effect keyed on entry.id only.
//
// `depth` is conditionally rendered: only meaningful when
// `positionMode == "depthN"`. The Swift side ignores it for top/
// bottom anyway, but hiding it keeps the form clean.

interface Props {
  entry: LorebookEntry;
  dispatchPatch: (patch: LorebookEntryPatch) => void;
  onBack: () => void;
  onDelete: () => void;
}

const ACTIVATION_MODES = ["constant", "keyed", "vectorised"] as const;
const POSITION_MODES = ["top", "bottom", "depthN"] as const;

export function LorebookEditor({ entry, dispatchPatch, onBack, onDelete }: Props) {
  const [draft, setDraft] = useState<LorebookEntry>(entry);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(entry);
  }, [entry.id]);

  const send = useDebouncedCallback(
    (patch: LorebookEntryPatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof LorebookEntry>(field: K, value: LorebookEntry[K]) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    send({ [field]: value as never } as LorebookEntryPatch);
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed entry)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
        <Button variant="destructive" onClick={onDelete}>
          Delete entry
        </Button>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
              placeholder="A short identifier shown in lists + logs."
            />
          </Field>
          <Field
            label="Activation mode"
            hint="constant: always inject. keyed: trigger on keys in recent prose. vectorised: Phase 5 R&D, no-op today."
          >
            <Select
              value={draft.activationMode}
              onChange={(e) =>
                update("activationMode", e.target.value as LorebookEntry["activationMode"])
              }
            >
              {ACTIVATION_MODES.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </Select>
          </Field>
          <Field
            label="Enabled"
            hint="Disabling skips this entry without removing it."
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
        </Section>

        <Section title="Content">
          <Field
            label="Content"
            hint="The text injected when this entry activates. Bracketed [Author's-Note]–style framing supported."
          >
            <Textarea
              rows={8}
              value={draft.content}
              onChange={(e) => update("content", e.target.value)}
            />
          </Field>
        </Section>

        <Section
          title="Keyed triggers"
          hint="Comma-separated in v1; one-per-row here. Keys match against recent prose for activationMode=keyed."
        >
          <Field label="Primary keys">
            <StringArrayEditor
              values={draft.keys}
              placeholder="key"
              onChange={(next) => update("keys", next)}
            />
          </Field>
          <Field
            label="Secondary keys"
            hint="Optional second filter — entry fires only if a primary key AND a secondary key both match."
          >
            <StringArrayEditor
              values={draft.secondaryKeys}
              placeholder="secondary key"
              onChange={(next) => update("secondaryKeys", next)}
            />
          </Field>
          <Field
            label="Recent-scenes scan budget"
            hint="How many recent scenes' prose to scan for key matches (default 3)."
          >
            <NumericField
              min={1}
              max={20}
              value={draft.maxRecentScenesScanned}
              onChange={(n) =>
                update("maxRecentScenesScanned", Math.max(1, n))
              }
            />
          </Field>
        </Section>

        <Section
          title="Placement"
          hint="Where in the prompt this entry's content lands."
        >
          <Field label="Position mode">
            <Select
              value={draft.positionMode}
              onChange={(e) =>
                update("positionMode", e.target.value as LorebookEntry["positionMode"])
              }
            >
              {POSITION_MODES.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </Select>
          </Field>
          {draft.positionMode === "depthN" && (
            <Field
              label="Depth"
              hint="Number of tokens from the end of the prompt to insert at."
            >
              <NumericField
                min={0}
                value={draft.depth ?? 0}
                onChange={(n) => update("depth", n)}
              />
            </Field>
          )}
          <Field
            label="Priority"
            hint="Higher = injected first when context budget is tight."
          >
            <NumericField
              value={draft.priority}
              onChange={(n) => update("priority", n)}
            />
          </Field>
        </Section>

        <Section
          title="Sphiratrioth pattern"
          hint="Optional grouping for weighted roll-outcome (LOOM_NSFW §2.5)."
        >
          <Field
            label="Group"
            hint="Lorebook entries sharing a group form a roll bucket; one wins per Roll Outcome."
          >
            <Input
              value={draft.group ?? ""}
              placeholder="e.g. kink_outcome"
              onChange={(e) => update("group", e.target.value)}
            />
          </Field>
          <Field
            label="Weight"
            hint="Bias inside the group (1–100). Higher = more likely to win."
          >
            <NumericField
              min={0}
              max={100}
              value={draft.weight ?? 0}
              onChange={(n) => update("weight", n)}
            />
          </Field>
          <Field
            label="Sticky"
            hint="If set, the rolled scenario persists across scene shifts."
          >
            <label className="inline-flex items-center gap-2 text-sm text-loom-fg">
              <input
                type="checkbox"
                checked={draft.sticky}
                onChange={(e) => update("sticky", e.target.checked)}
              />
              <span>sticky</span>
            </label>
          </Field>
        </Section>
      </div>
    </div>
  );
}

function StringArrayEditor({
  values,
  placeholder,
  onChange,
}: {
  values: string[];
  placeholder?: string;
  onChange: (next: string[]) => void;
}) {
  return (
    <div className="space-y-2">
      {values.map((value, i) => (
        <div key={i} className="flex gap-2">
          <Input
            value={value}
            placeholder={placeholder}
            onChange={(e) => {
              const next = [...values];
              next[i] = e.target.value;
              onChange(next);
            }}
          />
          <Button
            variant="ghost"
            onClick={() => onChange(values.filter((_, j) => j !== i))}
            aria-label={`Remove ${placeholder ?? "item"}`}
          >
            ✕
          </Button>
        </div>
      ))}
      <Button variant="ghost" onClick={() => onChange([...values, ""])}>
        + Add {placeholder ?? "item"}
      </Button>
    </div>
  );
}
