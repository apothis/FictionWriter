import { useEffect, useState } from "react";
import type {
  Character,
  CharacterCustomField,
  CharacterKink,
  CharacterPatch,
  KinkStance,
  Relationship,
  SceneSummary,
} from "../types";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { Select } from "../components/ui/Select";
import { Button } from "../components/ui/Button";
import { Tabs } from "../components/ui/Tabs";
import { Section, Field } from "../components/EditorLayout";
import { useDebouncedCallback } from "../lib/useDebouncedCallback";
import { FactsExaminer } from "./FactsExaminer";

// Phase 4.5 Sessions 2 + 4 — full character editor. All `Character`
// fields surfaced, plus an Accepted Facts tab (Session 4) for the
// per-scene KNOWS list with delete affordance.
//
// State model: local `draft` mirrors the input character; on user
// edit, `draft` updates immediately AND a debounced intent
// dispatches to Swift. The reset effect keys on `character.id`
// only — snapshot pushes that update the SAME character don't
// clobber in-flight typing.

type Tab = "fields" | "facts";

interface Props {
  character: Character;
  allCharacters: Character[];
  scenes: SceneSummary[];
  dispatchPatch: (patch: CharacterPatch) => void;
  onDeleteFact: (sceneId: string, factId: string) => void;
  onBack: () => void;
}

const ROLES = ["protagonist", "antagonist", "supporting", "minor", "narrator"];
const INJECTION_MODES = ["constant", "keyed"] as const;
const CUSTOM_FIELD_KINDS = ["text", "longText", "number", "boolean", "enum"];

export function CharacterEditor({
  character,
  allCharacters,
  scenes,
  dispatchPatch,
  onDeleteFact,
  onBack,
}: Props) {
  const [draft, setDraft] = useState<Character>(character);
  const [tab, setTab] = useState<Tab>("fields");

  // Reset draft (and snap back to the fields tab) only when a
  // DIFFERENT character is selected. Intentionally character.id —
  // snapshot pushes for the same character should not interrupt
  // mid-edit nor close the facts tab if the user is on it.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    setDraft(character);
    setTab("fields");
  }, [character.id]);

  const send = useDebouncedCallback(
    (patch: CharacterPatch) => dispatchPatch(patch),
    250,
  );

  function update<K extends keyof Character>(field: K, value: Character[K]) {
    setDraft((prev) => ({ ...prev, [field]: value }));
    send({ [field]: value as never } as CharacterPatch);
  }

  const factCount = Object.values(character.knownFactsBySceneId).reduce(
    (sum, facts) => sum + facts.length,
    0,
  );

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-loom-border px-6 py-3">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <span className="truncate text-sm font-medium text-loom-fg">
          {draft.name || "(unnamed)"}
        </span>
        <Tabs<Tab>
          className="ml-auto"
          tabs={[
            { value: "fields", label: "Fields" },
            { value: "facts", label: "Accepted facts", count: factCount },
          ]}
          value={tab}
          onChange={setTab}
        />
      </header>
      {tab === "facts" ? (
        <div className="flex-1 overflow-auto px-6 py-5">
          <FactsExaminer
            character={character}
            scenes={scenes}
            onDeleteFact={onDeleteFact}
          />
        </div>
      ) : (
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

        <Section
          title="Kinks"
          hint="What this character brings to a scene. Free-form — the list suggests common terms but accepts anything. Rendered into the bible entry so the model writes them consistently."
        >
          <KinksEditor
            values={draft.kinks ?? []}
            onChange={(next) => update("kinks", next)}
          />
        </Section>

        <Section
          title="Intimate anatomy"
          hint="Sexual/intimate body detail. Deliberately kept OUT of the always-on description so it can't leak into clothed, non-explicit prose. Injected only when the scene is explicit (on-screen or higher) AND this character is shown undressed in the scene."
        >
          <Textarea
            rows={4}
            value={draft.intimateAnatomy ?? ""}
            placeholder="Intimate anatomy detail — surfaces only once this character is undressed in an explicit scene."
            onChange={(e) => update("intimateAnatomy", e.target.value)}
          />
        </Section>

        <Section title="Custom fields" hint="Free-form extension slots for fandom-specific or one-off metadata.">
          <CustomFieldsEditor
            values={draft.customFields}
            onChange={(next) => update("customFields", next)}
          />
        </Section>
        </div>
      )}
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

const KINK_STANCES: { value: KinkStance; label: string }[] = [
  { value: "into", label: "into" },
  { value: "curious", label: "curious" },
  { value: "softLimit", label: "soft limit" },
  { value: "hardLimit", label: "hard limit" },
];

// A curated suggestion list — the input still accepts free text
// (the research warned against a rigid taxonomy).
const KINK_SUGGESTIONS = [
  "restraint", "bondage", "praise", "degradation", "dominance",
  "submission", "power exchange", "edging", "overstimulation",
  "voyeurism", "exhibitionism", "roleplay", "sensation play",
  "impact play", "breath play", "pain", "marking", "aftercare",
  "dirty talk", "teasing", "service", "primal play",
];

function KinksEditor({
  values,
  onChange,
}: {
  values: CharacterKink[];
  onChange: (next: CharacterKink[]) => void;
}) {
  return (
    <div className="space-y-2">
      <datalist id="kink-suggestions">
        {KINK_SUGGESTIONS.map((k) => (
          <option key={k} value={k} />
        ))}
      </datalist>
      {values.map((kink, i) => (
        <div key={i} className="flex gap-2">
          <Input
            value={kink.name}
            placeholder="kink"
            list="kink-suggestions"
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...kink, name: e.target.value };
              onChange(next);
            }}
          />
          <Select
            value={kink.stance}
            onChange={(e) => {
              const next = [...values];
              next[i] = { ...kink, stance: e.target.value as KinkStance };
              onChange(next);
            }}
          >
            {KINK_STANCES.map((st) => (
              <option key={st.value} value={st.value}>{st.label}</option>
            ))}
          </Select>
          <Button
            variant="ghost"
            onClick={() => onChange(values.filter((_, j) => j !== i))}
            aria-label="Remove kink"
          >
            ✕
          </Button>
        </div>
      ))}
      <Button
        variant="ghost"
        onClick={() => onChange([...values, { name: "", stance: "into" }])}
      >
        + Add kink
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
