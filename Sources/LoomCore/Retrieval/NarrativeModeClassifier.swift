import Foundation

/// Production-shape narrative-mode classifier — Phase 5 scope-lock #5
/// per [`LOOM_NARRATIVE_MODE_SPIKE.md`](../../LOOM_NARRATIVE_MODE_SPIKE.md)
/// §10 verdict. Two-pass composition:
///
/// 1. **Heuristic dialogue-gate first** — quote-density catches
///    dialogue at 87% recall + 100% precision on the spike gold. Wins
///    decisively over gemma-31B-zero-shot's 37% dialogue recall.
/// 2. **LLM for the residual** — when the heuristic doesn't say
///    `dialogue`, fall through to the caller-supplied LLM closure
///    (production: gemma-31B + flat GBNF enum classifier, per
///    [LOOM_NARRATIVE_MODE_SPIKE](../../LOOM_NARRATIVE_MODE_SPIKE.md)
///    §3.2(b) and the empirical zero-shot result that clears the 70%
///    accuracy floor).
///
/// LLM nil-return (network failure, parser error, etc.) falls back to
/// the heuristic's verdict — a defensible mode is better than a nil
/// `modality` slot in the index sidecar.
///
/// The classifier itself does no networking; the LLM closure is
/// caller-supplied, keeping this module pure-data and Swift-testable
/// without a live Kobold server.
public enum NarrativeModeClassifier {
    public static func classify(
        _ text: String,
        via llm: (String) -> NarrativeMode?
    ) -> NarrativeMode {
        let heuristic = NarrativeModeHeuristic.classify(text)
        if heuristic == .dialogue {
            return .dialogue
        }
        if let llmVerdict = llm(text) {
            return llmVerdict
        }
        return heuristic
    }
}
