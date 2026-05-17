import { useEffect, useMemo, useState } from "react";
import { Button } from "../components/ui/Button";
import { Input } from "../components/ui/Input";
import { Textarea } from "../components/ui/Textarea";
import { cn } from "../lib/cn";
import {
  postCloseWindow,
  requestCreatePlannedProject,
  requestGenerateOutline,
  subscribeToPlannedSnapshots,
} from "./bridge";
import { StyleEditor } from "./StyleEditor";

// `#styles` boots the bundle straight into the style-library editor
// as a standalone window (opened from the menu); the default shows
// the guided-creation wizard. Read once at module load.
const STANDALONE_STYLES = window.location.hash === "#styles";
import type {
  GeneratedOutline,
  LengthScenario,
  PlannedProjectConfig,
  PlannedProjectSnapshot,
  Scene,
  Style,
} from "./types";

// The guided-creation wizard. Six steps: premise+sketch -> length ->
// styles -> generate -> review/edit the outline -> create. The outline
// pipeline runs on the writer model (Swift side); this surface is the
// editable scaffold per LOOM_PLANNED_PROJECT.md §6 Phase 4.

const LENGTHS: { id: LengthScenario; name: string; range: string }[] = [
  { id: "flashFiction", name: "Flash fiction", range: "100–1,000 words · one scene" },
  { id: "shortStory", name: "Short story", range: "1,000–7,500 words · a few scenes" },
  { id: "novelette", name: "Novelette", range: "7,500–17,500 words" },
  { id: "novella", name: "Novella", range: "17,500–40,000 words · chaptered" },
  { id: "novel", name: "Novel", range: "40,000–120,000 words · chaptered" },
];

const STEP_TITLES = [
  "Premise & character",
  "Length",
  "Styles",
  "Generate the outline",
  "Review the outline",
  "Create the project",
];

export function WizardApp() {
  const [snapshot, setSnapshot] = useState<PlannedProjectSnapshot | null>(null);
  const [step, setStep] = useState(0);
  const [editingStyles, setEditingStyles] = useState(false);

  const [premise, setPremise] = useState("");
  const [characterSketch, setCharacterSketch] = useState("");
  const [lengthScenario, setLengthScenario] = useState<LengthScenario>("shortStory");
  const [assignedStyleIds, setAssignedStyleIds] = useState<string[]>([]);

  const [outline, setOutline] = useState<GeneratedOutline | null>(null);
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState<string | null>(null);

  const [title, setTitle] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const [created, setCreated] = useState(false);

  useEffect(() => subscribeToPlannedSnapshots(setSnapshot), []);

  const frameworkId = snapshot?.frameworks[0]?.id ?? "save-the-cat";

  const config: PlannedProjectConfig = useMemo(
    () => ({ premise, characterSketch, lengthScenario, frameworkId, assignedStyleIds }),
    [premise, characterSketch, lengthScenario, frameworkId, assignedStyleIds],
  );

  if (!snapshot) {
    return (
      <div className="flex h-screen items-center justify-center text-sm text-loom-fg-tertiary">
        Awaiting the style library…
      </div>
    );
  }

  if (STANDALONE_STYLES) {
    // Standalone window — "Done" closes the window rather than
    // returning to a wizard step.
    return (
      <StyleEditor initialStyles={snapshot.styles} onClose={postCloseWindow} />
    );
  }

  if (editingStyles) {
    return (
      <StyleEditor
        initialStyles={snapshot.styles}
        onClose={() => setEditingStyles(false)}
      />
    );
  }

  function toggleStyle(id: string) {
    setAssignedStyleIds((ids) =>
      ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id],
    );
  }

  async function generate() {
    setGenerating(true);
    setGenError(null);
    try {
      const result = await requestGenerateOutline(config);
      setOutline(result);
      setStep(4);
    } catch (e) {
      setGenError(e instanceof Error ? e.message : String(e));
    } finally {
      setGenerating(false);
    }
  }

  async function create() {
    if (!outline) return;
    setCreating(true);
    setCreateError(null);
    try {
      await requestCreatePlannedProject(title.trim(), config, outline);
      setCreated(true);
    } catch (e) {
      setCreateError(e instanceof Error ? e.message : String(e));
    } finally {
      setCreating(false);
    }
  }

  const canAdvance =
    step === 0
      ? premise.trim().length > 0 && characterSketch.trim().length > 0
      : step === 4
        ? outline != null
        : true;

  return (
    <div className="flex h-screen flex-col bg-loom-bg text-loom-fg">
      <Stepper step={step} />
      <div className="min-h-0 flex-1 overflow-y-auto px-8 py-6">
        <h1 className="mb-4 text-lg font-semibold">{STEP_TITLES[step]}</h1>

        {step === 0 && (
          <div className="flex max-w-2xl flex-col gap-5">
            <Field
              label="Plot premise"
              hint="A few sentences. What happens, and to whom?"
            >
              <Textarea
                rows={4}
                value={premise}
                onChange={(e) => setPremise(e.target.value)}
                placeholder="A burnt-out locksmith is hired for one last job…"
              />
            </Field>
            <Field
              label="Character sketch"
              hint="The protagonist. The leading name seeds a Bible character."
            >
              <Textarea
                rows={4}
                value={characterSketch}
                onChange={(e) => setCharacterSketch(e.target.value)}
                placeholder="Mara Voss, late forties — meticulous, distrustful, tired of the trade."
              />
            </Field>
          </div>
        )}

        {step === 1 && (
          <div className="flex max-w-2xl flex-col gap-2">
            {LENGTHS.map((l) => (
              <Card
                key={l.id}
                selected={lengthScenario === l.id}
                onClick={() => setLengthScenario(l.id)}
              >
                <div className="font-medium">{l.name}</div>
                <div className="text-xs text-loom-fg-tertiary">{l.range}</div>
              </Card>
            ))}
          </div>
        )}

        {step === 2 && (
          <StyleStep
            styles={snapshot.styles}
            assigned={assignedStyleIds}
            onToggle={toggleStyle}
            onManage={() => setEditingStyles(true)}
          />
        )}

        {step === 3 && (
          <GenerateStep
            config={config}
            styles={snapshot.styles}
            generating={generating}
            error={genError}
            onGenerate={generate}
          />
        )}

        {step === 4 && outline && (
          <OutlineEditor outline={outline} onChange={setOutline} />
        )}

        {step === 5 && (
          <CreateStep
            title={title}
            onTitle={setTitle}
            creating={creating}
            created={created}
            error={createError}
            onCreate={create}
          />
        )}
      </div>

      <footer className="flex items-center justify-between border-t border-loom-border px-8 py-3">
        <Button
          variant="ghost"
          disabled={step === 0 || created}
          onClick={() => setStep((s) => Math.max(0, s - 1))}
        >
          Back
        </Button>
        <span className="text-xs text-loom-fg-tertiary">
          Step {step + 1} of {STEP_TITLES.length}
        </span>
        {step < 3 && (
          <Button disabled={!canAdvance} onClick={() => setStep((s) => s + 1)}>
            Continue
          </Button>
        )}
        {step === 3 && <span className="w-16" />}
        {step === 4 && <Button onClick={() => setStep(5)}>Continue</Button>}
        {step === 5 && <span className="w-16" />}
      </footer>
    </div>
  );
}

function Stepper({ step }: { step: number }) {
  return (
    <div className="flex gap-1 px-8 pt-4">
      {STEP_TITLES.map((_, i) => (
        <div
          key={i}
          className={cn(
            "h-1 flex-1 rounded-full",
            i <= step ? "bg-loom-accent" : "bg-loom-border",
          )}
        />
      ))}
    </div>
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
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium">{label}</span>
      {hint && <span className="text-xs text-loom-fg-tertiary">{hint}</span>}
      {children}
    </label>
  );
}

function Card({
  selected,
  onClick,
  children,
}: {
  selected: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-lg border px-4 py-3 text-left transition-colors",
        selected
          ? "border-loom-accent bg-loom-accent/10"
          : "border-loom-border bg-loom-bg-elevated hover:bg-loom-bg-input",
      )}
    >
      {children}
    </button>
  );
}

function StyleStep({
  styles,
  assigned,
  onToggle,
  onManage,
}: {
  styles: Style[];
  assigned: string[];
  onToggle: (id: string) => void;
  onManage: () => void;
}) {
  const genres = styles.filter((s) => s.type === "genre");
  const registers = styles.filter((s) => s.type === "register");
  return (
    <div className="flex max-w-3xl flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <p className="text-xs text-loom-fg-tertiary">
          Styles thread into every generation call. Mix freely — genre and
          register are kept on separate prompt channels. Optional.
        </p>
        <Button variant="ghost" className="shrink-0" onClick={onManage}>
          Manage library
        </Button>
      </div>
      <StyleGroup title="Genre" styles={genres} assigned={assigned} onToggle={onToggle} />
      <StyleGroup
        title="Register"
        styles={registers}
        assigned={assigned}
        onToggle={onToggle}
      />
    </div>
  );
}

function StyleGroup({
  title,
  styles,
  assigned,
  onToggle,
}: {
  title: string;
  styles: Style[];
  assigned: string[];
  onToggle: (id: string) => void;
}) {
  return (
    <div className="flex flex-col gap-2">
      <h2 className="text-sm font-semibold text-loom-fg-secondary">{title}</h2>
      <div className="grid grid-cols-2 gap-2">
        {styles.map((s) => (
          <Card key={s.id} selected={assigned.includes(s.id)} onClick={() => onToggle(s.id)}>
            <div className="font-medium">{s.name}</div>
            <div className="mt-0.5 line-clamp-2 text-xs text-loom-fg-tertiary">
              {s.descriptor}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function GenerateStep({
  config,
  styles,
  generating,
  error,
  onGenerate,
}: {
  config: PlannedProjectConfig;
  styles: Style[];
  generating: boolean;
  error: string | null;
  onGenerate: () => void;
}) {
  const assigned = styles.filter((s) => config.assignedStyleIds.includes(s.id));
  const lengthName = LENGTHS.find((l) => l.id === config.lengthScenario)?.name ?? "";
  return (
    <div className="flex max-w-2xl flex-col gap-4">
      <div className="rounded-lg border border-loom-border bg-loom-bg-elevated p-4 text-sm">
        <SummaryRow label="Premise" value={config.premise} />
        <SummaryRow label="Character" value={config.characterSketch} />
        <SummaryRow label="Length" value={lengthName} />
        <SummaryRow
          label="Styles"
          value={assigned.length ? assigned.map((s) => s.name).join(", ") : "None"}
        />
      </div>
      <p className="text-xs text-loom-fg-tertiary">
        The outline is generated on the writer model in staged passes —
        beats, chapter map, then scenes. This can take a minute.
      </p>
      {error && (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-400">
          {error}
        </div>
      )}
      <Button disabled={generating} onClick={onGenerate}>
        {generating ? "Generating…" : "Generate outline"}
      </Button>
    </div>
  );
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex gap-3 border-b border-loom-border py-1.5 last:border-0">
      <span className="w-20 shrink-0 text-loom-fg-tertiary">{label}</span>
      <span className="min-w-0 flex-1 whitespace-pre-wrap">{value}</span>
    </div>
  );
}

function OutlineEditor({
  outline,
  onChange,
}: {
  outline: GeneratedOutline;
  onChange: (o: GeneratedOutline) => void;
}) {
  const sceneById = new Map(outline.scenes.map((s) => [s.id, s]));

  function patchScene(id: string, patch: Partial<Scene>) {
    onChange({
      ...outline,
      scenes: outline.scenes.map((s) => (s.id === id ? { ...s, ...patch } : s)),
    });
  }

  function patchChapter(partIdx: number, chIdx: number, patch: Record<string, unknown>) {
    const parts = outline.manuscript.parts.map((p, pi) =>
      pi !== partIdx
        ? p
        : {
            ...p,
            chapters: p.chapters.map((c, ci) => (ci === chIdx ? { ...c, ...patch } : c)),
          },
    );
    onChange({ ...outline, manuscript: { ...outline.manuscript, parts } });
  }

  const flat = outline.manuscript.parts.length === 0;

  return (
    <div className="flex max-w-3xl flex-col gap-4">
      <p className="text-xs text-loom-fg-tertiary">
        Edit titles and summaries before creating the project. Scene counts
        are fixed by the chosen length.
      </p>
      {flat
        ? outline.manuscript.orphanedSceneIds.map((id, i) => {
            const scene = sceneById.get(id);
            return scene ? (
              <SceneRow key={id} index={i} scene={scene} onPatch={patchScene} />
            ) : null;
          })
        : outline.manuscript.parts.map((part, pi) =>
            part.chapters.map((ch, ci) => (
              <div key={ch.id} className="flex flex-col gap-2">
                <Input
                  className="font-semibold"
                  value={ch.title}
                  onChange={(e) => patchChapter(pi, ci, { title: e.target.value })}
                />
                <Textarea
                  rows={2}
                  className="text-xs"
                  value={ch.summary ?? ""}
                  placeholder="Chapter summary"
                  onChange={(e) => patchChapter(pi, ci, { summary: e.target.value })}
                />
                <div className="flex flex-col gap-2 border-l border-loom-border pl-3">
                  {ch.sceneIds.map((id, si) => {
                    const scene = sceneById.get(id);
                    return scene ? (
                      <SceneRow key={id} index={si} scene={scene} onPatch={patchScene} />
                    ) : null;
                  })}
                </div>
              </div>
            )),
          )}
    </div>
  );
}

function SceneRow({
  index,
  scene,
  onPatch,
}: {
  index: number;
  scene: Scene;
  onPatch: (id: string, patch: Partial<Scene>) => void;
}) {
  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-loom-border bg-loom-bg-elevated p-3">
      <div className="flex items-center gap-2">
        <span className="text-xs text-loom-fg-tertiary">Scene {index + 1}</span>
        <Input
          value={scene.title}
          onChange={(e) => onPatch(scene.id, { title: e.target.value })}
        />
      </div>
      <Textarea
        rows={2}
        className="text-xs"
        value={scene.summary}
        placeholder="Scene summary"
        onChange={(e) => onPatch(scene.id, { summary: e.target.value })}
      />
    </div>
  );
}

function CreateStep({
  title,
  onTitle,
  creating,
  created,
  error,
  onCreate,
}: {
  title: string;
  onTitle: (v: string) => void;
  creating: boolean;
  created: boolean;
  error: string | null;
  onCreate: () => void;
}) {
  if (created) {
    return (
      <div className="flex max-w-2xl flex-col gap-2">
        <div className="rounded-md border border-loom-accent/40 bg-loom-accent/10 p-4 text-sm">
          Project created. You can close this window — your new project is
          open in Loom.
        </div>
      </div>
    );
  }
  return (
    <div className="flex max-w-2xl flex-col gap-4">
      <Field label="Project title" hint="The .loom bundle is named for this.">
        <Input
          value={title}
          onChange={(e) => onTitle(e.target.value)}
          placeholder="Nightlock"
        />
      </Field>
      {error && (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-400">
          {error}
        </div>
      )}
      <Button disabled={creating || title.trim().length === 0} onClick={onCreate}>
        {creating ? "Creating…" : "Create project"}
      </Button>
    </div>
  );
}
