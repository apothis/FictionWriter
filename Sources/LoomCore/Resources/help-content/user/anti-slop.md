# Anti-slop phrases

"Slop" is the family of cliché phrasings local models over-produce — *"a shiver down her spine,"* *"voice barely above a whisper,"* *"a testament to,"* *"his ministrations."* You know them when you see them; the model reaches for them because they're high-probability in its training data. Loom's **anti-slop list** suppresses them at the source.

## How it works — and why it's not a prompt blacklist

This is the important distinction. There are two ways you might try to stop a model writing a phrase:

1. **Tell it not to in the prompt** ("never write 'shivers down the spine'"). This **doesn't work** — the model paraphrases around the instruction, substituting synonyms, and naming the phrase can even make it more likely to appear. Prompt blacklists get paraphrase-evaded.
2. **Stop it at the sampler.** This is what Loom does. The phrase list is sent to KoboldCpp as `banned_strings` — a **phrase-level backtracking sampler**. As the model generates, if it starts to emit a banned phrase, the sampler backtracks and picks a different continuation. The phrase never makes it into the output because the sampler won't let those tokens through.

Because it's enforced at generation time rather than asked for in the prompt, it's reliable in a way a prompt instruction isn't. This is the one place Loom uses a "list of forbidden things" — and it works precisely because it's a sampler constraint, not a prompt directive. (See **NSFW / dark-fiction posture** for why the prompt-side constraints are all positive instead.)

## The default list

New projects are seeded with a curated default list, grouped by the kind of slop:

- **Body-reaction clichés** — *"shivers down her spine," "her breath hitched," "heart pounded in her chest," "let out a breath she didn't know she was holding."*
- **Voice / expression clichés** — *"voice barely above a whisper," "a ghost of a smile," "her eyes sparkled," "eyes glinted with mischief."*
- **Grand-abstraction clichés** — *"a testament to," "a symphony of," "a kaleidoscope of," "the air was thick with."*
- **Explicit-scene euphemism slop** — *"her core," "his ministrations," "waves of pleasure," "claimed her mouth."*
- **Filler intensifiers** — *"couldn't help but," "little did she know," "impossibly."*

The list is a starting point, not gospel — it reflects the most common local-model tells. Tune it for your project.

## Editing the list

**Bible → Edit Anti-slop List…** opens the editor. Add the phrases your model overuses, remove any you actually want (some projects genuinely want "a ghost of a smile"). The list is per-project — different novels can ban different things.

A few authoring notes:

- **Phrases are matched as lowercase substrings.** "her core" matches regardless of capitalisation, and matches inside a longer sentence.
- **Ban the phrase, not the word.** Banning a whole common word ("core," "claimed") will misfire on legitimate uses. The defaults are multi-word phrases for this reason.
- **Both pronoun forms.** The defaults include "her" and "his" variants separately ("shivers down her spine" / "shivers down his spine") because they're distinct substrings. Add both if your cast is mixed.

## The one limitation

The backtracking sampler can undo a phrase it catches *early*, but it can only backtrack a few tokens at a time. A banned phrase that drifts in after a long run of high-probability tokens can occasionally slip through — the sampler can't reach back far enough to undo it. In practice this is rare, and adding a recurring offender to the list still helps: the backtracking succeeds on the large majority of attempts even if it misses the occasional one.

If a specific phrase keeps slipping through despite being on the list, that's the sampler hitting its backtrack window — not the list being ignored. The fix is usually upstream: the prose context is steering hard toward that phrase. Tighten the preceding sentences or the Author's Note.

## Where it's stored

The list lives on `ProjectSettings.antiSlopPhrases` inside `project.json`, so it travels with the project. Seeded from the defaults at project creation; fully editable thereafter.

## See also

- **NSFW / dark-fiction posture** — why prompt-side constraints are positive, and this is the exception.
- **Settings — app-level + per-project** — where project-scoped tools live.
- **When generation refuses or feels off** — the broader toolkit when prose comes out wrong.
