import { useEffect, useState } from "react";
import type {
  Character,
  CharacterCustomField,
  CharacterPatch,
  Relationship,
} from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Select } from "../components/ui/Select";
import { Button } from "../components/ui/Button";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";

// Phase 4.5 Session 2 — full character editor. All `Character`
// fields except `avatarPath` (Session 8+ — deferred per
// LOOM_BIBLE_WORKSPACE.md §8.4) and `knownFactsBySceneId` (managed
// via the facts examiner, Session 4).
//
// State model: local `draft` mirrors the input character; on user
// edit, `draft` updates immediately (so the input renders the
// typed value, not the stale snapshot value) AND a debounced
// intent dispatches to Swift. The reset effect keys on
// `character.id` only — snapshot pushes that update the SAME
// character don't clobber in-flight typing.

interface Props {
  character: Character;
  allCharacters: Character[];
  dispatchPatch: (patch: CharacterPatch) => void;
  onBack: () => void;
}

const ROLES = ["protagonist", "antagonist", "supporting", "minor", "narrator"];
const INJECTION_MODES = ["constant", "keyed"] as const;
const CUSTOM_FIELD_KINDS = ["text", "longText", "number", "boolean", "enum"];

export function CharacterEditor({ character, allCharacters, dispatchPatch, onBack }: Props) {
  const [draft, setDraft] = useState<Character>(character);

  // Reset draft only when a DIFFERENT character is selected
  // (intentionally character.id, not the whole character — snapshot
  // pushes for the same character should not interrupt mid-edit).
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(character);
  }, [character.id]);

  const send = useDebouncedCallback(
    (patch: CharacterPatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof Character>(field: K, value: Character[K]) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    send({ [field]: value as never } as CharacterPatch);
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed)"}
        </span>
        <span className="ml-auto text-[10px] uppercase tracking-wider text-loom-fg-tertiary">
          Edits autosave
        </span>
      </header>
      <div className="flex-1 overflow-auto px-6 py-5">
        <Section title="Identity">
          <Field label="Name">
            <Input
              value={draft.name}
              onChange={(e) => update("name", e.target.value)}
            />
          </Field>
          <Field label="One-line">
            <Input
              value={draft.oneLine}
              onChange={(e) => update("oneLine", e.target.value)}
              placeholder="A short tagline for this character."
            />
          </Field>
          <Field label="Role">
            <Select
              value={draft.role}
              onChange={(e) => update("role", e.target.value as Character["role"])}
            >
              {ROLES.map((r) => (
                <option key={r} value={r}>{r}</option>
              ))}
            </Select>
          </Field>
          <Field label="Injection mode" hint="constant: always inject. keyed: only when name/alias appears in recent prose.">
            <Select
              value={draft.injectionMode}
              onChange={(e) =>
                update("injectionMode", e.target.value as Character["injectionMode"])
              }
            >
              {INJECTION_MODES.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </Select>
          </Field>
          <Field label="Aliases" hint="One per row. Used as keyed-injection triggers and @-mention targets.">
            <StringArrayEditor
              values={draft.aliases}
              placeholder="alias"
              onChange={(next) => update("aliases", next)}
            />
          </Field>
        </Section>

        <Section title="Description">
          <Field label="Description">
            <Textarea
              rows={4}
              value={draft.description}
              onChange={(e) => update("description", e.target.value)}
            />
          </Field>
          <Field label="Personality">
            <Textarea
              rows={3}
              value={draft.personality}
              onChange={(e) => update("personality", e.target.value)}
            />
          </Field>
          <Field label="Appearance">
            <Textarea
              rows={3}
              value={draft.appearance}
              onChange={(e) => update("appearance", e.target.value)}
            />
          </Field>
          <Field label="Voice">
            <Textarea
              rows={3}
              value={draft.voice}
              onChange={(e) => update("voice", e.target.value)}
            />
          </Field>
          <Field label="Goals">
            <Textarea
              rows={3}
              value={draft.goals}
              onChange={(e) => update("goals", e.target.value)}
            />
          </Field>
        </Section>

        <Section title="Relationships">
          <RelationshipsEditor
            values={draft.relationships}
            allCharacters={allCharacters.filter((c) => c.id !== character.id)}
            onChange={(next) => update("relationships", next)}
          />
        </Section>

        <Section title="Canon brief" hint="Optional. Used by the Phase 5.b canon-ingestion pipeline.">
          <Textarea
            rows={4}
            value={draft.canonBrief ?? ""}
            placeholder="Pasted-in canon notes from a fandom wiki, etc."
            onChange={(e) => update("canonBrief", e.target.value)}
          />
        </Section>

        <Section title="Custom fields" hint="Free-form extension slots for fandom-specific or one-off metadata.">
          <CustomFieldsEditor
            values={draft.customFields}
            onChange={(next) => update("customFields", next)}
          />
        </Section>
      </div>
    </div>
  );
}

// --------------------------------------------------------------
// Section + Field layout primitives
// --------------------------------------------------------------

function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="mb-3 text-xs font-medium uppercase tracking-wider text-loom-fg-secondary">
        {title}
      </h2>
      {hint && (
        <p className="mb-3 text-[11px] text-loom-fg-tertiary">{hint}</p>
      )}
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between">
        <label className="text-xs font-medium text-loom-fg-secondary">
          {label}
        </label>
        {hint && (
          <span className="ml-2 text-[10px] italic text-loom-fg-tertiary">
            {hint}
          </span>
        )}
      </div>
      {children}
    </div>
  );
}

// --------------------------------------------------------------
// Array editors
// --------------------------------------------------------------

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

function RelationshipsEditor({
  values,
  allCharacters,
  onChange,
}: {
  values: Relationship[];
  allCharacters: Character[];
  onChange: (next: Relationship[]) => void;
}) {
  if (allCharacters.length === 0 && values.length === 0) {
    return (
      <p className="text-xs italic text-loom-fg-tertiary">
        Add at least one other character to create a relationship.
      </p>
    );
  }
  return (
    <div className="space-y-3">
      {values.map((rel, i) => (
        <div
          key={i}
          className="grid grid-cols-[1fr_1fr_2fr_auto] gap-2 rounded-lg border border-loom-border bg-loom-bg-elevated p-3"
        >
          <Select
            value={rel.toCharacterId}
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...rel, toCharacterId: e.target.value };
              onChange(next);
            }}
          >
            <option value="">(target)</option>
            {allCharacters.map((c) => (
              <option key={c.id} value={c.id}>{c.name || "(unnamed)"}</option>
            ))}
          </Select>
          <Input
            value={rel.kind}
            placeholder="kind (spouse, rival…)"
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...rel, kind: e.target.value };
              onChange(next);
            }}
          />
          <Input
            value={rel.notes}
            placeholder="notes"
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...rel, notes: e.target.value };
              onChange(next);
            }}
          />
          <Button
            variant="ghost"
            onClick={() => onChange(values.filter((_, j) => j !== i))}
            aria-label="Remove relationship"
          >
            ✕
          </Button>
        </div>
      ))}
      <Button
        variant="ghost"
        onClick={() =>
          onChange([
            ...values,
            { toCharacterId: allCharacters[0]?.id ?? "", kind: "", notes: "" },
          ])
        }
        disabled={allCharacters.length === 0}
      >
        + Add relationship
      </Button>
    </div>
  );
}

function CustomFieldsEditor({
  values,
  onChange,
}: {
  values: CharacterCustomField[];
  onChange: (next: CharacterCustomField[]) => void;
}) {
  return (
    <div className="space-y-3">
      {values.map((field, i) => (
        <div
          key={i}
          className="grid grid-cols-[1fr_2fr_auto_auto] gap-2 rounded-lg border border-loom-border bg-loom-bg-elevated p-3"
        >
          <Input
            value={field.label}
            placeholder="label"
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...field, label: e.target.value };
              onChange(next);
            }}
          />
          <Input
            value={field.value}
            placeholder="value"
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...field, value: e.target.value };
              onChange(next);
            }}
          />
          <Select
            value={field.kind}
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...field, kind: e.target.value };
              onChange(next);
            }}
          >
            {CUSTOM_FIELD_KINDS.map((k) => (
              <option key={k} value={k}>{k}</option>
            ))}
          </Select>
          <Button
            variant="ghost"
            onClick={() => onChange(values.filter((_, j) => j !== i))}
            aria-label="Remove field"
          >
            ✕
          </Button>
        </div>
      ))}
      <Button
        variant="ghost"
        onClick={() => onChange([...values, { label: "", value: "", kind: "text" }])}
      >
        + Add custom field
      </Button>
    </div>
  );
}
