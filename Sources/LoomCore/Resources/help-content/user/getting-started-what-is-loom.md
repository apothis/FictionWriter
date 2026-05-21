# What Loom is

Loom is a macOS app for writing long-form fiction with help from a local AI model. Essays, short stories, novellas, novels — anything where you sit down and draft prose for more than a few paragraphs.

It looks and works like a document editor. You write in a normal editor pane; AI generations happen at your cursor, inserted directly into the text. There's no chat panel, no transcript of turns, no conversation with a bot — just prose, the way you'd write it yourself, with the model nudging it forward when you ask.

## "Local" is the load-bearing word

Loom doesn't talk to OpenAI, Anthropic, or any cloud service. The AI model that writes for you runs on your own Mac, or on another machine on your network. That has three concrete consequences:

- **No content filtering.** Loom is plumbing. It doesn't moderate what you write, what the model writes, or what you ask for. Whatever your chosen model is willing to produce, you get. Loom never editorialises and never inserts safety theatre.
- **No terms of service governing your fiction.** Your manuscript never leaves your network. There's no provider to ban you, throttle you, or change the rules under your feet.
- **You provide the model.** Loom needs a local model server to talk to — one for the writing model, optionally a second for smaller background tasks (style retrieval, fact extraction, contradiction checking). The "Configure your model servers" section walks through which ones and how.

If you've never run a local LLM before, the first-time setup is a one-time hurdle but not a hard one — download a model file, start the server, point Loom at it.

## When Loom is the right tool

- **Long-form prose.** Loom holds onto your story bible — characters, settings, lorebook entries, relationships, what each character knows when — and threads it into every generation. That's the differentiator versus pasting a few paragraphs into a chatbot.
- **Drafting at speed.** Continue, Expand, Rewrite (voice / tense / length / POV), Show-Don't-Tell, Brainstorm, Critique, Bridge — generation modes for the moves you actually make while drafting.
- **Heavy NSFW or extreme-topic fiction.** This is the use case that pushes you away from cloud tools in the first place. Loom is built for it: per-character anatomy and kinks, relationship sheets (Dynamics), uncensored-by-default sampler defaults, anti-slop banned-phrases lists. See "NSFW / dark-fiction posture" in the Reference half.
- **Iterating across many scenes.** Project → Parts → Chapters → Scenes (Scrivener-shaped). Corkboard view. Snapshots before AI rewrites.

## When Loom isn't the right tool

- **Outlining from a blank page.** Loom has a Brainstorm mode, but it isn't a planning suite. If you want a beat grid or a 2D plot timeline, a dedicated outlining app will serve you better.
- **Collaboration.** Loom is single-user. No cloud sync, no multi-author editing — deferred indefinitely.
- **Chatting with a character.** That's roleplay, and there are tools shaped for it. Loom is a document editor; it doesn't speak in turns.
- **Writing on the road without your Mac.** Local-only means local-only. There's no mobile companion and no web client.

## What's next

In order, the first-time-user path through this Getting Started book is:

1. **Install + first launch** — get the app running.
2. **Configure your model servers** — point Loom at KoboldCpp and (optionally) Ollama.
3. **Your first project** — make a project, write a scene.
4. **Your first scene + first generation** — run Continue and see what comes back.
5. **What to do when generation refuses or feels off** — the small toolkit when the model balks or drifts.
6. **Where your work lives on disk** — projects are plain directories of markdown; you can poke at them with any editor.

Pick the next section from the TOC on the left.
