import Foundation

/// Narrative mode of a prose chunk — the per-scene-type retrieval
/// tag carried on `ReferenceTextIndex.Chunk.modality`. Phase 5
/// production scope-lock #5 ([`LOOM_PLAN.md`](../../LOOM_PLAN.md) §5)
/// validates filling this slot via gemma-4-31B classification at
/// ingest, per [`LOOM_NARRATIVE_MODE_SPIKE.md`](../../LOOM_NARRATIVE_MODE_SPIKE.md).
///
/// Taxonomy extended from [`LOOM_RESEARCH.md`](../../LOOM_RESEARCH.md)
/// §O.4's original four (action / dialogue / interiority /
/// description) with **summary** (Marshall 1998, Card 1999, Le Guin
/// *Steering the Craft* — scene-vs-summary is the orthogonal pace
/// axis) and **mixed** (genuine 50/50 chunks — the gold's noise
/// floor and the classifier's "I'm unsure" output).
///
/// The schema slot (`ReferenceTextIndex.Chunk.modality`) is `String?`
/// rather than `NarrativeMode?` to forward-tolerate unknown labels
/// from future enum extensions; this enum formalises the v1 value
/// space and the GBNF grammar fragment for classifier prompts.
public enum NarrativeMode: String, CaseIterable, Equatable, Codable {
    /// Physical action / external events. Active verbs, scene-time
    /// progression.
    case action

    /// Character speech, with or without attribution beats.
    /// Quote-density is the surface signal.
    case dialogue

    /// Internal thought / feeling / free-indirect discourse.
    /// Cognition verbs and subjective register.
    case interiority

    /// Settings, objects, sensory environment. Suspended time,
    /// adjective density, sensory verbs.
    case description

    /// Compressed-time narration ("for three weeks…", "by autumn…",
    /// "she had been seeing him for months").
    case summary

    /// Genuinely 50/50 across two modes. Used by the gold as the
    /// noise floor and by the classifier as its "uncertain" output.
    /// Retrieval that filters by modality should treat `mixed` as a
    /// wildcard / opt-out rather than a queryable category.
    case mixed

    /// The GBNF alternation fragment used by the classifier's flat-
    /// enum grammar. Generated from `allCases` so adding a new mode
    /// in v2 doesn't require touching the grammar separately.
    /// Format: `"action" | "dialogue" | ... | "mixed"` — flat, no
    /// JSON wrapper, no nested structure (Bastan et al. 2025
    /// "Lost in Space" failure-mode fix).
    public static var gbnfAlternation: String {
        allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " | ")
    }
}
