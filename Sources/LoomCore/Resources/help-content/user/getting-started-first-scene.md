# Your first scene + first generation

You have a project open, Scene 1 selected, and an empty editor with a blinking cursor. Time to write something and ask the model to keep going.

## The pieces you're looking at

Three things, top to bottom:

1. **The editor** — the big text area in the middle. This is where you type and where generated prose lands. Plain text; no formatting toolbar, no rich-text shenanigans.
2. **The generation tray** — sits below the editor. It has a row of buttons (**Continue**, **Expand**, **Rewrite**, **Brainstorm**, **Critique**), a single-line instruction field, and a small **▸ History** disclosure.
3. **The sidebar** on the left — your project tree. Right now it just shows "Scene 1," but once you have parts and chapters this is where you'll navigate them.

For this walk-through, ignore the sidebar and the modes-other-than-Continue.

## Step 1 — Write a seed

Click into the editor and type a couple of sentences. Anything will do — a description, a line of dialogue, the opening of a scene. Don't overthink it. Example:

```
The lighthouse keeper had not spoken to another person in eleven days.
He told himself this was preferable. He was, in fact, lying to himself
without quite knowing it.
```

You're giving the model **context**. The more grounded the seed (specific noun, a turn of phrase, an implied conflict), the more the model has to build from.

## Step 2 — Position your cursor

Put the cursor at the end of your seed text. That's where the generation will be inserted — Loom's **Continue** mode generates from the cursor outward.

(If you leave the cursor in the middle of your text by accident, Continue still works; it inserts right where the cursor is. That's occasionally useful — you can drop a model-written paragraph between two of your own — but for now keep it at the end.)

## Step 3 — Click Continue

In the generation tray below the editor, click **Continue**.

Several things happen at once:

- The editor goes read-only — you can't edit while a generation is in flight, to avoid two writers (you and the model) colliding on the same text.
- A spinner appears in the tray.
- Prose starts streaming into the editor at the cursor, a word or short phrase at a time.
- A small **state label** to the right of the tray buttons shows what's happening (e.g. "Continuing…").

How fast it streams depends on your hardware and your model. A 24B-parameter writer on Apple Silicon is comfortably readable; a 70B model on a Mac mini is slower but readable.

**If you change your mind**, press **Esc** or **⌘.** to cancel mid-stream. Whatever was already inserted stays; the rest is discarded. Re-edit and try again.

## Step 4 — Accept, Reject, or Redo

When generation finishes, the tray buttons swap: instead of the mode buttons, you'll see three new ones — **Accept ⏎**, **Reject ⌫**, **Keep & Redo ⌘⇧R**. This is the **acceptance window**, and you stay in it until you pick one.

- **Accept** (or press **Return**) — keep the inserted prose as-is. Editor unlocks, cursor lands at the end of the new text, ready for you to write more or run Continue again.
- **Reject** (or press **Backspace/Delete**) — discard everything that was just inserted. Editor returns to the state it was in before you clicked Continue. Use this when the model wandered off, broke voice, or just felt wrong.
- **Keep & Redo** (or press **⌘⇧R**) — keep the inserted prose AND immediately run Continue again from the new cursor position. The fastest way to chain two paragraphs of generation when you like the first.

You'll use Reject more than you expect, especially as you're learning what your model writes well. That's normal — the model's a collaborator, not an oracle.

## Step 5 — Try a per-call instruction

The single-line field in the tray (placeholder text: **"Instruction for this generation (optional)…"**) is where you can steer one specific generation without changing the rest of your project.

Type something like:

```
more dramatic
```

or:

```
keep it terse — three sentences, no metaphors
```

then click Continue again. Loom passes the instruction through to the model wrapped in the conventional bracketed `[...]` Author's Note form (it works better than chat-shaped instructions for fiction models). The field clears after each call so it doesn't silently bleed into the next one.

## What just happened, briefly

When you clicked Continue, Loom assembled a **prompt** for the model — everything before your cursor, framed with a system prompt, with your project's Story Bible threaded in, plus a few neighbour scenes and any retrieved style exemplars from your references. You don't see most of this; that's the point. But it's all there in **▸ History** at the bottom of the tray, if you ever want to audit what the model actually saw. Loom never hides what it sent.

## What you can do next

Once you have your first few paragraphs:

- Run **Continue** again to keep going.
- Select a word or sentence and click **Expand** to grow it into a fuller paragraph.
- Select a phrase, click **Rewrite**, pick a sub-mode (voice / tense / length / POV / show-don't-tell). See **Generation modes — full catalogue** in the Reference half for the full picture.
- Make a Character or Setting entry in the Story Bible so the model knows who's in your story (see **Story Bible — Characters, Settings, Objects, Factions** in the Reference half).

If the model refuses to write something — apologises, summarises around it, breaks into a meta-commentary — that's the next page: **What to do when generation refuses or feels off**.
