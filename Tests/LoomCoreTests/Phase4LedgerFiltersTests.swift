import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 8 — the §10.5 production filters between
/// extraction and Suggestions display. Three independent pure-data
/// passes, all consuming pre-computed embedding vectors (the async
/// embedding-fetch orchestration lives at the AppState layer).
///
/// 1. `LedgerFilters.deduplicate(...)` — collapses paraphrase clusters
///    by cosine. Catches both bible-side dupes (same fact already
///    in the character's ledger from a prior pass) and intra-batch
///    dupes (the extractor emitting two phrasings of the same fact in
///    one call — observed live, e.g. "Mia decided to tell Karim" +
///    "Mia confirmed that she would tell Karim tomorrow").
/// 2. `LedgerFilters.validateEvidence(...)` — drops facts whose
///    `evidenceQuote` has no high-cosine sentence in the scene's
///    prose. Catches model lightly editorialising speech tags.
/// 3. `LedgerFilters.filterPromptLeakage(...)` — drops facts whose
///    body cosine-matches the §3.3 prompt instructions. Catches the
///    rare prompt-text echo seen in the LOOM_LEDGER_SPIKE §9.2 logs.
///
/// All three are fail-open for missing embeddings: if a suggestion's
/// required embedding isn't in the dict, the suggestion is kept (the
/// orchestrator's contract is to fetch every embedding before
/// invoking the filter; a missing key implies an orchestrator bug
/// rather than malicious data, and dropping silently would harm the
/// NSFW content-neutrality directive — see HANDOFF §15.8 + LOOM_NSFW
/// §3).
func phase4LedgerFiltersTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerFilters")

    // MARK: - Helpers

    // 2-D unit vectors so cosine = dot product, easy to hand-verify.
    let vA: [Float] = [1.0, 0.0]
    let vAparaphrase: [Float] = [0.95, 0.3122]  // ≈ cos 0.95 with vA
    let vB: [Float] = [0.0, 1.0]                // orthogonal to vA
    let vC: [Float] = [0.7071, 0.7071]          // cos 0.7071 with vA

    func makeSuggestion(
        character: UUID,
        factText: String,
        evidence: String = "",
        scene: UUID = UUID()
    ) -> LedgerSuggestion {
        let kf = KnownFact(
            id: UUID(),
            fact: factText,
            sourceSceneId: scene,
            certainty: .asserted,
            addedAt: Date()
        )
        return LedgerSuggestion(characterId: character, fact: kf, evidenceQuote: evidence)
    }

    // MARK: - deduplicate

    s.test("LedgerFilters.deduplicate keeps suggestions when nothing matches above threshold") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia drank wine")
        let result = LedgerFilters.deduplicate(
            suggestions: [suggestion],
            existingFactsByCharacter: [:],
            embeddings: ["Mia drank wine": vA],
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
        try expectEqual(result[0].fact.fact, "Mia drank wine")
    }

    s.test("LedgerFilters.deduplicate drops a paraphrase of an existing bible fact") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia was drinking wine")
        let result = LedgerFilters.deduplicate(
            suggestions: [suggestion],
            existingFactsByCharacter: [mia: ["Mia drank wine"]],
            embeddings: [
                "Mia was drinking wine": vAparaphrase,
                "Mia drank wine": vA,
            ],
            threshold: 0.85
        )
        try expectEqual(result.count, 0)
    }

    s.test("LedgerFilters.deduplicate collapses intra-batch paraphrases (keeps first)") {
        let mia = UUID()
        let s1 = makeSuggestion(character: mia, factText: "Mia drank wine")
        let s2 = makeSuggestion(character: mia, factText: "Mia was drinking wine")
        let result = LedgerFilters.deduplicate(
            suggestions: [s1, s2],
            existingFactsByCharacter: [:],
            embeddings: [
                "Mia drank wine": vA,
                "Mia was drinking wine": vAparaphrase,
            ],
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
        try expectEqual(result[0].fact.fact, "Mia drank wine")
    }

    s.test("LedgerFilters.deduplicate scopes per-character — Mia dupes don't filter Anders") {
        let mia = UUID()
        let anders = UUID()
        let miaSuggestion = makeSuggestion(character: mia, factText: "Mia drank wine")
        let andersSuggestion = makeSuggestion(character: anders, factText: "Mia drank wine")
        let result = LedgerFilters.deduplicate(
            suggestions: [miaSuggestion, andersSuggestion],
            existingFactsByCharacter: [mia: ["Mia drank wine"]],
            embeddings: ["Mia drank wine": vA],
            threshold: 0.85
        )
        // Mia's suggestion dupes the bible; Anders's references the
        // same TEXT but is scoped to a different character so it stays.
        try expectEqual(result.count, 1)
        try expectEqual(result[0].characterId, anders)
    }

    s.test("LedgerFilters.deduplicate fails open on missing embedding") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia drank wine")
        let result = LedgerFilters.deduplicate(
            suggestions: [suggestion],
            existingFactsByCharacter: [mia: ["Mia was drinking wine"]],
            embeddings: [:],   // none available
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
    }

    s.test("LedgerFilters.deduplicate keeps near-misses just below threshold") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia walked away")
        let result = LedgerFilters.deduplicate(
            suggestions: [suggestion],
            existingFactsByCharacter: [mia: ["Mia drank wine"]],
            embeddings: [
                "Mia walked away": vC,   // cos 0.7071 with vA
                "Mia drank wine": vA,
            ],
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
    }

    // MARK: - validateEvidence

    s.test("LedgerFilters.validateEvidence keeps suggestions whose evidence matches a scene sentence") {
        let mia = UUID()
        let suggestion = makeSuggestion(
            character: mia,
            factText: "Mia drank wine",
            evidence: "Mia was drinking wine"
        )
        let result = LedgerFilters.validateEvidence(
            suggestions: [suggestion],
            sceneSentences: ["Mia drank wine in the kitchen"],
            embeddings: [
                "Mia was drinking wine": vAparaphrase,
                "Mia drank wine in the kitchen": vA,
            ],
            threshold: 0.65
        )
        try expectEqual(result.count, 1)
    }

    s.test("LedgerFilters.validateEvidence drops suggestions when no scene sentence matches") {
        let mia = UUID()
        let suggestion = makeSuggestion(
            character: mia,
            factText: "Mia drank wine",
            evidence: "Mia hallucinated quote"
        )
        let result = LedgerFilters.validateEvidence(
            suggestions: [suggestion],
            sceneSentences: ["Anders looked out the window"],
            embeddings: [
                "Mia hallucinated quote": vA,
                "Anders looked out the window": vB,   // orthogonal → cos 0
            ],
            threshold: 0.65
        )
        try expectEqual(result.count, 0)
    }

    s.test("LedgerFilters.validateEvidence fails open on empty evidence string") {
        let mia = UUID()
        // The diff stage carries `evidenceQuote: ""` when the extractor
        // omitted it. We can't validate emptiness, so keep — accepting
        // the suggestion is the user's call.
        let suggestion = makeSuggestion(character: mia, factText: "Mia drank wine", evidence: "")
        let result = LedgerFilters.validateEvidence(
            suggestions: [suggestion],
            sceneSentences: ["Mia drank wine in the kitchen"],
            embeddings: ["Mia drank wine in the kitchen": vA],
            threshold: 0.65
        )
        try expectEqual(result.count, 1)
    }

    s.test("LedgerFilters.validateEvidence fails open on missing evidence embedding") {
        let mia = UUID()
        let suggestion = makeSuggestion(
            character: mia,
            factText: "Mia drank wine",
            evidence: "evidence text"
        )
        let result = LedgerFilters.validateEvidence(
            suggestions: [suggestion],
            sceneSentences: ["Mia drank wine in the kitchen"],
            embeddings: ["Mia drank wine in the kitchen": vA],  // evidence missing
            threshold: 0.65
        )
        try expectEqual(result.count, 1)
    }

    s.test("LedgerFilters.validateEvidence keeps when even one sentence matches above threshold") {
        let mia = UUID()
        let suggestion = makeSuggestion(
            character: mia,
            factText: "Mia drank wine",
            evidence: "Mia was drinking wine"
        )
        let result = LedgerFilters.validateEvidence(
            suggestions: [suggestion],
            sceneSentences: [
                "Anders looked out the window",
                "Mia drank wine in the kitchen",
            ],
            embeddings: [
                "Mia was drinking wine": vAparaphrase,
                "Anders looked out the window": vB,
                "Mia drank wine in the kitchen": vA,
            ],
            threshold: 0.65
        )
        try expectEqual(result.count, 1)
    }

    // MARK: - filterPromptLeakage

    s.test("LedgerFilters.filterPromptLeakage keeps facts unrelated to the prompt") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia drank wine")
        let promptEmbedding = vB
        let result = LedgerFilters.filterPromptLeakage(
            suggestions: [suggestion],
            promptEmbedding: promptEmbedding,
            embeddings: ["Mia drank wine": vA],   // orthogonal to prompt
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
    }

    s.test("LedgerFilters.filterPromptLeakage drops facts that echo the prompt") {
        let mia = UUID()
        // The model leaks the prompt instruction back as a "fact".
        let leaked = makeSuggestion(
            character: mia,
            factText: "List one entry per fact the character DID or LEARNED in this scene"
        )
        let promptEmbedding = vA
        let result = LedgerFilters.filterPromptLeakage(
            suggestions: [leaked],
            promptEmbedding: promptEmbedding,
            embeddings: ["List one entry per fact the character DID or LEARNED in this scene": vAparaphrase],
            threshold: 0.85
        )
        try expectEqual(result.count, 0)
    }

    s.test("LedgerFilters.filterPromptLeakage fails open on missing fact embedding") {
        let mia = UUID()
        let suggestion = makeSuggestion(character: mia, factText: "Mia drank wine")
        let result = LedgerFilters.filterPromptLeakage(
            suggestions: [suggestion],
            promptEmbedding: vA,
            embeddings: [:],
            threshold: 0.85
        )
        try expectEqual(result.count, 1)
    }

    // MARK: - extractionPromptInstruction constant

    s.test("LedgerExtraction.extractionPromptInstruction is non-empty and excludes scene-specific content") {
        let instruction = LedgerExtraction.extractionPromptInstruction
        try expectFalse(instruction.isEmpty)
        // Sanity: the instruction shouldn't carry character names or
        // scene text from any specific call — it must be a stable
        // string the AppState orchestrator can embed once at boot.
        try expectFalse(instruction.contains("Characters (names + aliases):"))
        try expectFalse(instruction.contains("Scene:"))
    }

    return s
}
