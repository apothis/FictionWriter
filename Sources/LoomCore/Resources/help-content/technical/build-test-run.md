# Build / test / run

The operations for working in this tree. All commands run from the repo root.

## Build — `./build.sh`

One command builds the whole app:

```
./build.sh
```

The chain (`build.sh`):

1. **`scripts/build-bible-workspace.sh`** — builds the four WKWebView bundles with `bun` + Vite (bails loud if `bun` is missing). Each is a separate `vite build` (IIFE format, selected by `LOOM_BUNDLE`), HTML post-processed for `file://`, synced into `Resources/<Panel>/`.
2. **`swift build -c release --product Loom`** — compiles `LoomCore` + the `Loom` executable.
3. **Assemble `Loom.app`** — copies the binary + `Info.plist` + every SwiftPM resource bundle (`*.bundle`, including `Loom_LoomCore.bundle`) into `Loom.app/Contents/`.
4. **Code-sign** — with the stable "Loom Local" identity if present, else ad-hoc (with a warning).

First build is minutes (pulls SwiftPM deps + compiles cold). Subsequent builds are seconds-to-tens-of-seconds.

### Prerequisites

- macOS 14+ (`Info.plist` `LSMinimumSystemVersion`).
- Xcode Command Line Tools (the Swift compiler).
- `bun` — `brew install oven-sh/bun/bun` or the official installer.

No Xcode-proper, npm, or Python needed for the standard build. (Python is only needed to *regenerate* the CoreML model / ONNX export, which ship prebuilt for most checkouts — see below.)

## Run — `./run.sh`

```
./run.sh
```

Runs the built binary directly (`exec ./Loom.app/Contents/MacOS/Loom`). This is the dev path — it bypasses Launch Services' Local Network privacy re-prompt that fires on every rebuild under ad-hoc signing. Use `open Loom.app` (or Finder) for a "real" Launch Services launch.

## Code signing — `./scripts/create-signing-identity.sh`

One-off, optional but recommended:

```
./scripts/create-signing-identity.sh
```

Creates a stable self-signed "Loom Local" identity in the login keychain. macOS TCC (Local Network, etc.) keys grants off the app's designated code requirement; under ad-hoc signing that's derived from the CDHash, which churns every build → the Local Network grant is revoked on every rebuild. A stable identity keeps the grant. Idempotent.

## Test — `swift run LoomCoreTests`

```
swift run LoomCoreTests
```

**Tests are not XCTest.** `LoomCoreTests` is an `executableTarget` (not a `testTarget`) running an in-house harness, **TestKit** (`Tests/LoomCoreTests/TestKit.swift`). There is no `swift test` configuration — `swift run LoomCoreTests` is the command.

The harness:

- **`Tests/LoomCoreTests/main.swift`** declares `let suites: [TestSuite] = [ ... ]` and ends with `exit(TestRunner.run(suites))`. The exit code is non-zero on any failure.
- A suite registers cases with `suite.test("name") { ... }`. A case fails if it throws — assertions (`expect`, `expectEqual`, `expectGreaterThan`, `expectNil`, `expectNotNil`, `expectTrue`/`expectFalse`, `expectThrows`) throw `TestFailure` on mismatch.
- Test bodies are `@MainActor`. For async code under test, **`awaitSync { await ... }`** bridges async to the synchronous test context.
- `@testable import LoomCore` works via the `-enable-testing` flag on the LoomCore target (debug only).

### Adding a test suite

1. Write `Tests/LoomCoreTests/<Feature>Tests.swift` exposing a `TestSuite` (the convention is a static factory or a top-level value).
2. Add it to the `suites` array in `main.swift`.
3. `swift run LoomCoreTests`.

The repo runs ~2045 cases green. The TDD convention is strict: every code change starts with a failing test (red → green → commit), and every schema change pins an "old-JSON-decodes" forward-load case.

### Testing callback APIs

Loom is callback-async (no `async/await` in production). When stubbing an async API in a test, **defer the completion + flush** rather than calling `completion(...)` synchronously inside the stub — a synchronous completion hides `[weak self]` lifetime + ordering bugs that only manifest with real async dispatch.

## Spike runners — `swift run <Tool>`

The `Tools/*` executable targets are on-demand eval runners, not part of the test suite. They hit live local-LLM servers and emit markdown reports:

```
swift run LedgerSpike            # knowledge-ledger extraction eval
swift run EntityDiscoverySpike   # entity-discovery precision/recall
swift run RagSpike               # style-retrieval probe
swift run ContinuityAuditSpike   # continuity-audit run + report
# … see Tools/ for the full list
```

Each reads its config from env vars (e.g. `LOOM_SPIKE_OLLAMA_URL`, default `http://localhost:11434/`) and prints its argument shape. Full per-tool table in **T.10 — Spike runners**.

## Regenerating the bundled models

Two resources ship prebuilt but can be regenerated:

- **Wegmann CoreML model** — `Tools/CoreMLProbe/build_mlpackage.py` produces `Resources/StyleEmbedding/StyleEmbedding.mlpackage`. Needs Python + coremltools. Gitignored; regenerate locally if missing (the app falls back to `PythonEmbeddingClient` against a venv if absent).
- **GLiNER ONNX export** — `Tools/GLiNERProbe/export_gliner_onnx.py` produces the `Resources/GLiNER/` bundle. Ships in-repo (one-off export).

The four webview bundles + the CoreML model are **gitignored** — regenerated before `swift build` by the build scripts. A fresh checkout's first `./build.sh` builds the webview bundles; the CoreML model needs its Python build script run once (or the venv fallback).

## Common build failures

- **`bun is not installed`** — install bun; restart the shell so `$PATH` updates.
- **`file modified during build` / non-exhaustive switch in unrelated files** — another session is editing `main`; wait for a green tree.
- **Blank webview panel after launch** — a webview bundle build problem the first run swallowed; re-run `./build.sh` and watch for bun errors.
- **Local Network re-prompt every build** — you're ad-hoc signing; run `create-signing-identity.sh` once.

## See also

- **Repo layout** — what the build produces, file by file.
- **Spike runners** (T.10) — the `Tools/*` eval runners.
- **Architecture overview** — the threading + concurrency posture the test conventions follow.
- `build.sh`, `run.sh`, `scripts/build-bible-workspace.sh`, `scripts/create-signing-identity.sh` — the scripts themselves.
