# Install + first launch

Loom is currently distributed as source you build yourself, not as a downloadable .app or DMG. The build is short — a handful of terminal commands the first time, then `./build.sh` after that — but you will need to open Terminal.

This page is for your first time. If you're already past it, the order is `./build.sh` (compile) → `./run.sh` (launch). Done.

## What you'll need

| Tool | Why | How |
|---|---|---|
| **macOS 14 or later** | The minimum the app declares. | Apple menu → About This Mac. If you're on macOS 13 or earlier, you'll need to update. |
| **Xcode Command Line Tools** | Gives you the Swift compiler that builds Loom. | Terminal: `xcode-select --install`. If you already have Xcode installed, you're done. |
| **bun** | A small JavaScript build tool. Loom uses it to build the side panels (the Story Bible window, the in-app Help you're reading right now, etc.). | See instructions below the table. |
| **git** | Comes with the Command Line Tools above. Used to pull the source. | (no action — installed with the CLT) |

You don't need Node.js, npm, Python, or Xcode itself — just the Command Line Tools and bun.

**Installing bun.** Two paths, pick whichever fits:

```
brew install oven-sh/bun/bun
```

if you have Homebrew. Otherwise, the official installer:

```
curl -fsSL https://bun.sh/install | bash
```

Restart Terminal after either one so the new `$PATH` takes effect.

## Step 1 — Get the source

Clone or download the Loom repository from wherever you got it. Then in Terminal, `cd` into the directory:

```
cd path/to/FictionWriter
```

Throughout this guide, that's the working directory all commands run in.

## Step 2 — Build the app

```
./build.sh
```

The first build will:

1. Build the web bundles (the Story Bible window, the Planned Project wizard, the Project Tools panel, this Help system).
2. Compile the Swift code.
3. Assemble `Loom.app` in the project root.
4. Sign the app so macOS will let you launch it.

First build takes a few minutes — it has to pull Swift package dependencies and compile everything from scratch. Subsequent builds are much faster (seconds to tens of seconds) because most of the work is cached.

If the build fails loudly with a message about `bun is not installed`, install bun (see the prerequisites table above) and re-run.

## Step 3 — Stable code signing (optional but recommended)

This one is a quality-of-life fix. Skip it and Loom still works, but macOS will re-prompt for Local Network permission every single time you rebuild — annoying once you start iterating.

The fix is a one-time command:

```
./scripts/create-signing-identity.sh
```

This creates a self-signed certificate in your login keychain named "Loom Local". From then on, `./build.sh` automatically picks it up and signs the app with a stable identity, so the Local Network permission grant you give it once stays valid across rebuilds.

The script is idempotent — re-running it does nothing if the identity already exists.

## Step 4 — First launch

Two ways to launch:

```
./run.sh
```

This is the dev path — it runs the binary directly and is what you'll use day-to-day. Slightly faster, slightly more reliable for permission handling.

Or, for a "normal" Mac launch, double-click `Loom.app` in Finder, or:

```
open Loom.app
```

The first time Loom launches, **macOS will ask whether to allow it Local Network access**. Say yes. Loom needs this to reach your local model server (which runs on your Mac or another machine on your home network). Deny it and generation will silently fail — Loom can't talk to a model server at all without it.

## Step 5 — What you'll see

A single empty window with:

- An editor pane in the middle (empty — no project loaded).
- The menu bar at the top with **File**, **Edit**, **View**, etc.
- No project sidebar yet — you'll get one once you open or create a project.

You're now ready to point Loom at a model server. Next stop: **Configure your model servers**.

## If something went wrong

- **`./build.sh: Permission denied`** — make it executable: `chmod +x build.sh run.sh scripts/*.sh`.
- **`xcrun: error: invalid active developer path`** — Command Line Tools aren't installed or got broken. Re-run `xcode-select --install`.
- **Build halts complaining about `bun`** — install bun (prerequisites table). If you installed it just now, restart Terminal so the new `$PATH` takes effect.
- **App launches but the window is blank** — almost always a side-panel build problem. Try `./build.sh` again; it'll surface bun errors that the first run swallowed.
- **macOS says "Loom can't be opened because Apple cannot check it for malicious software"** — right-click `Loom.app` in Finder → **Open**. You only need to do this once per signed identity. (Or, easier: use `./run.sh` instead.)
- **Built fine, runs fine, but the Local Network prompt never came back after you denied it** — System Settings → Privacy & Security → Local Network → toggle Loom on. macOS only asks once.

If you're past first launch and stuck on something else, the **Troubleshooting** section in the Reference half is the next place to look.
