# Configure your model servers

Loom doesn't have a built-in AI model. You point it at one (or two) running on your Mac or your local network. This page is the one-time setup; you'll typically not touch it again unless you swap models or move servers.

## Two roles, two servers

Loom uses up to two backend servers, with different jobs:

| Role | What it does | Backend | Required? |
|---|---|---|---|
| **Writer** | All creative prose generation — Continue, Expand, Rewrite, Show-Don't-Tell, Brainstorm, Bridge. The big, expressive model you want for prose. | KoboldCpp | Yes. Loom can't generate anything without this. |
| **Extractor** | Background structured-text side-tasks — knowledge ledger ("what does this character know?"), entity discovery (auto-found characters / places / objects), continuity audit, style retrieval. Wants a small, fast, schema-friendly model. | Ollama | Optional. Without it, Loom still writes; you just lose the bible-side intelligence. |

You can run both on the same machine, or on different machines on your LAN, or on the same machine as Loom — Loom doesn't care where they live as long as it can reach them over HTTP.

Why two servers? The two roles want very different models. The writer model is heavy, creative, often uncensored — slow per call, but you only run it when you ask. The extractor runs a constrained JSON-schema prompt against every scene you write; using a 24B+ creative model for that would be both wasteful and worse at the job. The split is on purpose.

## Step 1 — Set up the writer (KoboldCpp)

Loom expects [**KoboldCpp**](https://github.com/LostRuins/koboldcpp) for the writer role. It's a single-file binary that loads a GGUF model file and exposes a local HTTP API.

The short version:

1. **Get the binary.** Download the latest `koboldcpp-mac` release from the project's GitHub releases page. Apple Silicon users want the `-arm` flavour.
2. **Get a model.** Any GGUF model will work. For fiction with no content restrictions, popular choices include Goetia, Gemma-4-31B abliterated, and Midnight Miqu 70B — see the **NSFW / dark-fiction posture** section in the Reference half for the full list and tradeoffs. Models are 4–40 GB depending on size and quantisation; pick something that fits your RAM.
3. **Launch it.** Run the binary, point it at your GGUF file, accept the defaults. KoboldCpp serves on `http://localhost:5001` by default.
4. **Confirm it's up.** Visit `http://localhost:5001` in any browser — you should see KoboldCpp's own web UI.

KoboldCpp has thorough documentation on its own GitHub for sampler tuning, GPU offload, etc. Loom takes care of the per-call samplers; KoboldCpp's job is just to serve the model.

## Step 2 — Set up the extractor (Ollama, optional)

[**Ollama**](https://ollama.com) is a small-model serving tool that's friendlier than Kobold for the side-task workload. Skip this step entirely if you only want plain writing; come back to it when you want bible-side intelligence.

The short version:

1. **Install Ollama.** Download from the website above and run the installer. Ollama runs as a background service.
2. **Pull the extractor model.** Loom's pipelines are tuned for Gemma 4 2B. From Terminal: `ollama pull gemma4_2b`. Other small instruction-tuned models will work, but prompts and parse tolerances were calibrated against this one.
3. **Confirm it's up.** Ollama serves on `http://localhost:11434` by default. Open it in a browser — you should see `Ollama is running`.

## Step 3 — Add the servers in Loom

Open Loom's Settings window (**Loom → Settings…**, or press **⌘,**). Pick the **Servers** tab.

For each server, click **Add Server…** and fill in:

- **Name** — anything you like ("Home", "Kobold", "M3 Studio"). Just a label for the picker.
- **Base URL** — where the server lives. The form will pre-fill a placeholder for the kind you pick.
  - Kobold on this Mac: `http://localhost:5001`
  - Kobold on a LAN machine: `http://<that-machine-ip>:5001` (substitute the machine's IP — find it in System Settings → Network on that Mac)
  - Ollama on this Mac: `http://localhost:11434`
- **Kind** — Kobold (writer) or Ollama (extractor).

Click **Add**. Loom immediately probes the server to confirm it's reachable and to cache the model name + max context. If the probe fails, the entry is still saved — you can fix the URL later — but generation won't work until the server is reachable.

## Step 4 — Assign roles

Back in the Servers list, you'll see your added profiles. Select the row, then:

- **Set as Default** marks the Kobold profile as the writer. Required.
- **Set as Extractor** marks the Ollama profile as the extractor. Optional; click again to clear.

If you add your first server with the list empty, Loom auto-marks it as the default — one less click. The Extractor role is never auto-assigned; you have to opt in.

The roles list against each row in the Servers tab. A typical end state looks like:

```
Home — http://localhost:5001 (writer)
Local Ollama [Ollama] — http://localhost:11434 (extractor)
```

That's it. Close the Settings window. The next generation you trigger will use the writer; the next scene you finish will trigger an extractor pass in the background.

## Where this gets stored

Loom persists your server profiles to:

```
~/Library/Application Support/Loom/settings.json
```

That's app-wide — it travels with your Mac, not with any individual project. If you ever want to start clean, delete that file; Loom will recreate it on next launch with no servers configured.

## If something doesn't work

- **"Probe failed" right after adding** — Loom couldn't reach the URL you gave it. Open the URL in a browser; if the browser can't reach it either, the server isn't running, the port is wrong, or a firewall is in the way. If the browser CAN reach it but Loom can't, you probably denied Loom's Local Network permission on first launch — fix it in System Settings → Privacy & Security → Local Network.
- **The server's running but Loom says "no writer configured"** — you added the profile but didn't click **Set as Default**. Default = writer.
- **Generation works but no knowledge-ledger suggestions ever appear** — you don't have an extractor set, or Ollama isn't serving the model Loom's looking for. Check Settings → Servers; the extractor row should have `(extractor)` next to it. Confirm `ollama list` shows your pulled model.
- **A LAN server is reachable from your browser but not from Loom** — Local Network permission again. macOS gates this at the app level, and only prompts once.

Once both servers are up, the next stop is **Your first project**.
