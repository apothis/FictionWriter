import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #5 / LOOM_STORY_BIBLE §3 / LOOM_MEMORY §4.5 —
/// knowledge-ledger extraction pipeline (pure-data layer).
///
/// This is the load-bearing distinctive engineering for Loom: extract
/// per-character factual claims (with KNOWS / DOES NOT KNOW / MISTAKEN
/// certainty) from finished scene prose, so the next generation knows
/// what each POV character can and can't reference.
///
/// **Spike scope:** prompt builder + JSON response parser + scorer —
/// all pure-data, all TDD-first. The actual network call to the live
/// summariser-role server happens in the separate `LedgerSpike`
/// executable, which uses these pieces to run an eval against a
/// hand-graded fixture and emit a precision/recall report. That report
/// gates whether to build the full pipeline at full intent or defer
/// the extractor side to Phase 5 (LOOM_MEMORY §4.5 falsifiable
/// hypothesis: per-scene extraction is feasible at <13B; we're testing
/// at 27B, so the threshold is even lower).
func phase4LedgerExtractionTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerExtraction")

    // MARK: - Prompt builder (LOOM_STORY_BIBLE §3.3)

    s.test("prompt embeds the JSON character list with names + aliases") {
        let chars = [
            LedgerExtraction.CharacterRef(name: "Mia", aliases: ["Miss Vance", "the librarian"]),
            LedgerExtraction.CharacterRef(name: "Anders", aliases: []),
        ]
        let prompt = LedgerExtraction.buildExtractionPrompt(
            characters: chars,
            scenePose: "The wind picked up."
        )
        try expectTrue(
            prompt.lowercased().contains("character"),
            "prompt should mention characters"
        )
        try expectTrue(
            prompt.contains("\"name\":\"Mia\""),
            "expected serialized character Mia in prompt — got:\n\(prompt)"
        )
        try expectTrue(
            prompt.contains("\"Miss Vance\""),
            "expected Mia's alias in prompt"
        )
        try expectTrue(
            prompt.contains("\"name\":\"Anders\""),
            "expected serialized character Anders in prompt"
        )
    }

    s.test("prompt embeds the scene prose verbatim under the Scene header") {
        let chars = [LedgerExtraction.CharacterRef(name: "Mia", aliases: [])]
        let prose = "Mia opened the envelope and stared.\nThe letter was unsigned."
        let prompt = LedgerExtraction.buildExtractionPrompt(
            characters: chars,
            scenePose: prose
        )
        try expectTrue(prompt.contains("Scene:"), "prompt missing scene header")
        try expectTrue(prompt.contains(prose), "scene prose not embedded verbatim")
    }

    s.test("prompt asks for a JSON array of facts and frames the task as extraction") {
        let prompt = LedgerExtraction.buildExtractionPrompt(
            characters: [LedgerExtraction.CharacterRef(name: "X", aliases: [])],
            scenePose: ""
        )
        // The grammar (gbnfGrammar) is the load-bearing source of truth
        // for the schema — the prompt no longer needs to repeat schema
        // field names or the certainty enum. What the prompt MUST do:
        // (a) frame the task as fact-extraction, (b) include "JSON
        // array" so the model has a clear output shape in mind, (c)
        // include "fact" / "facts" to anchor what we want.
        // (LOOM_LEDGER_SPIKE §8.1: prompt-engineering minimised; grammar
        // does the structural enforcement.)
        try expectTrue(
            prompt.lowercased().contains("fact"),
            "prompt should frame the task around facts"
        )
        try expectTrue(
            prompt.contains("JSON array"),
            "prompt should request a JSON array — sets the model's frame"
        )
    }

    // MARK: - Response parser

    s.test("parser accepts a clean JSON array per the §3.3 schema") {
        let raw = """
        [
          {"character_id":"Mia","fact":"Mia learned the door was unlocked.","certainty":"asserted","evidence_quote":"The handle turned freely."},
          {"character_id":"Anders","fact":"Anders does not know Mia is in the flat.","certainty":"unknown","evidence_quote":"He stood on the landing."}
        ]
        """
        let parsed = try LedgerExtraction.parseExtractedFacts(raw)
        try expectEqual(parsed.count, 2)
        try expectEqual(parsed[0].characterId, "Mia")
        try expectEqual(parsed[0].certainty, .asserted)
        try expectEqual(parsed[1].characterId, "Anders")
        try expectEqual(parsed[1].certainty, .unknown)
    }

    s.test("parser tolerates a JSON array preceded/followed by chatty prose (model preamble)") {
        // Local models routinely wrap structured output in "Here are the
        // facts I extracted:\n[...]\nThat's it." Strip non-JSON pre/post
        // text by locating the outermost `[` ... `]` pair.
        let raw = """
        Here are the extracted facts:
        [
          {"character_id":"Mia","fact":"Mia is in the flat.","certainty":"asserted","evidence_quote":"She closed the door."}
        ]
        Let me know if you need more.
        """
        let parsed = try LedgerExtraction.parseExtractedFacts(raw)
        try expectEqual(parsed.count, 1)
        try expectEqual(parsed[0].characterId, "Mia")
    }

    s.test("parser returns an empty array on `[]`") {
        let parsed = try LedgerExtraction.parseExtractedFacts("[]")
        try expectEqual(parsed.count, 0)
    }

    s.test("parser throws on unparseable output (no JSON array at all)") {
        try expectThrows("expected throw on missing JSON array") {
            _ = try LedgerExtraction.parseExtractedFacts("I can't help with that.")
        }
    }

    s.test("parser drops entries with unknown certainty values, keeps valid siblings") {
        // Model occasionally invents certainty levels ("likely", "maybe").
        // Drop the invalid entries rather than throwing — the rest of
        // the extraction is still useful.
        let raw = """
        [
          {"character_id":"A","fact":"f1","certainty":"asserted","evidence_quote":"q"},
          {"character_id":"B","fact":"f2","certainty":"likely","evidence_quote":"q"},
          {"character_id":"C","fact":"f3","certainty":"suspected","evidence_quote":"q"}
        ]
        """
        let parsed = try LedgerExtraction.parseExtractedFacts(raw)
        try expectEqual(parsed.count, 2)
        try expectEqual(parsed[0].characterId, "A")
        try expectEqual(parsed[1].characterId, "C")
    }

    // MARK: - Scorer

    s.test("scorer reports perfect match when extracted == gold") {
        let gold = [
            LedgerExtraction.ExtractedFact(characterId: "Mia", fact: "Mia is here.", certainty: .asserted, evidenceQuote: "q1"),
        ]
        let extracted = gold
        let score = LedgerExtraction.score(extracted: extracted, gold: gold)
        try expectEqual(score.truePositives, 1)
        try expectEqual(score.falsePositives, 0)
        try expectEqual(score.falseNegatives, 0)
        try expectTrue(score.precision == 1.0, "expected precision 1.0, got \(score.precision)")
        try expectTrue(score.recall == 1.0, "expected recall 1.0, got \(score.recall)")
    }

    s.test("scorer counts a character_id + certainty match as a true positive (fact text need not be identical)") {
        // The scorer's "match" predicate is (character_id, certainty) +
        // fact-text similarity > 0.6 (Jaccard over normalised words).
        // Different wording of the same fact still counts.
        let gold = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia learned the door was unlocked.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia discovered that the door was unlocked.",
                certainty: .asserted, evidenceQuote: "q'"
            ),
        ]
        let score = LedgerExtraction.score(extracted: extracted, gold: gold)
        try expectEqual(score.truePositives, 1, "fact text similarity should match across wording")
    }

    s.test("scorer counts invented facts (no gold counterpart) as false positives") {
        let gold: [LedgerExtraction.ExtractedFact] = []
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia owns a cat.",
                certainty: .asserted, evidenceQuote: "(none — invented)"
            ),
        ]
        let score = LedgerExtraction.score(extracted: extracted, gold: gold)
        try expectEqual(score.falsePositives, 1)
        try expectEqual(score.truePositives, 0)
    }

    s.test("scorer counts missed gold facts as false negatives") {
        let gold = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia is in the flat.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let extracted: [LedgerExtraction.ExtractedFact] = []
        let score = LedgerExtraction.score(extracted: extracted, gold: gold)
        try expectEqual(score.falseNegatives, 1)
    }

    s.test("scorer's character-alias resolution treats an alias match as the same character") {
        // Gold says "Mia"; extracted says "Miss Vance" (alias). With an
        // alias map ["Miss Vance" → "Mia"], they should be considered
        // the same character.
        let gold = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia is in the flat.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Miss Vance", fact: "Miss Vance is in the flat.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let aliases: [String: String] = ["Miss Vance": "Mia", "the librarian": "Mia"]
        let score = LedgerExtraction.score(extracted: extracted, gold: gold, aliases: aliases)
        try expectEqual(score.truePositives, 1, "alias-resolved match should count as true positive")
    }

    // MARK: - GBNF grammar (LOOM_LEDGER_SPIKE §8.1)

    s.test("grammar describes a JSON array of ledger-fact objects") {
        let g = LedgerExtraction.gbnfGrammar()
        // Root must produce a JSON array.
        try expectTrue(g.contains("root"), "grammar must have a root production")
        try expectTrue(g.contains("\"[\""), "grammar must open with literal `[`")
        try expectTrue(g.contains("\"]\""), "grammar must close with literal `]`")
        // The fact object must constrain the four schema fields by name.
        try expectTrue(g.contains("character_id"), "schema field character_id missing from grammar")
        try expectTrue(g.contains("fact"), "schema field fact missing from grammar")
        try expectTrue(g.contains("certainty"), "schema field certainty missing from grammar")
        try expectTrue(g.contains("evidence_quote"), "schema field evidence_quote missing from grammar")
        // Certainty values must be restricted to the §3.3 enum. Per §8.3
        // the production extractor's grammar emits ONLY `asserted` —
        // `unknown` / `mistaken` are derived from scene-exposure rather
        // than extracted — but we keep the full enum here so the helper
        // is reusable when callers want it. The runtime grammar used by
        // LedgerSpike is built via `gbnfGrammar(certainties:)`.
        try expectTrue(g.contains("asserted"), "certainty `asserted` missing from grammar")
    }

    s.test("grammar can restrict certainty to a subset (asserted-only for Phase 4 #7)") {
        let g = LedgerExtraction.gbnfGrammar(certainties: [.asserted])
        try expectTrue(g.contains("asserted"), "asserted must be in restricted grammar")
        try expectFalse(g.contains("suspected"), "suspected must NOT appear in asserted-only grammar")
        try expectFalse(g.contains("mistaken"), "mistaken must NOT appear in asserted-only grammar")
    }

    return s
}
