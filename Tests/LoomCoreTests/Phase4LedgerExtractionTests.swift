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

    // MARK: - Embedding scorer (LOOM_LEDGER_SPIKE §10)

    s.test("cosineSimilarity returns 1.0 for identical vectors and 0 for orthogonal") {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]
        let c: [Float] = [0, 1, 0]
        try expectTrue(LedgerExtraction.cosineSimilarity(a, b) > 0.999, "identical → 1.0")
        try expectTrue(abs(LedgerExtraction.cosineSimilarity(a, c)) < 0.001, "orthogonal → 0")
    }

    s.test("cosineSimilarity returns 0 for empty inputs (degenerate case)") {
        try expectEqual(LedgerExtraction.cosineSimilarity([], []), 0.0)
        try expectEqual(LedgerExtraction.cosineSimilarity([1, 0], [0, 0]), 0.0)
    }

    s.test("embedding-scorer matches extracted facts to gold by cosine threshold (alias-resolved character + certainty + cosine≥threshold)") {
        // Build a synthetic embedding-by-text map. Two facts with similar
        // wording but different character names should NOT match (char
        // mismatch trumps cosine); two facts about the same character with
        // similar embeddings DO match.
        let goldEmb: [Float]      = [1, 0, 0, 0]
        let exNear: [Float]       = [0.9, 0.1, 0, 0]  // cosine ≈ 0.99
        let exFar: [Float]        = [0, 1, 0, 0]      // cosine = 0
        let embeddingFor: (String) -> [Float] = { txt in
            switch txt {
            case "Mia drank wine.": return goldEmb
            case "Mia was drinking wine.": return exNear
            case "Mia walked to the door.": return exFar
            default: return [0, 0, 0, 0]
            }
        }
        let gold = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia drank wine.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia was drinking wine.",
                certainty: .asserted, evidenceQuote: "q"
            ),
            LedgerExtraction.ExtractedFact(
                characterId: "Mia", fact: "Mia walked to the door.",
                certainty: .asserted, evidenceQuote: "q"
            ),
        ]
        let report = LedgerExtraction.scoreByEmbedding(
            extracted: extracted, gold: gold,
            embedding: embeddingFor, threshold: 0.7
        )
        try expectEqual(report.truePositives, 1, "near-cosine match → TP")
        try expectEqual(report.falsePositives, 1, "far-cosine non-match → FP")
        try expectEqual(report.falseNegatives, 0)
    }

    s.test("embedding-scorer respects alias resolution for character_id") {
        let goldEmb: [Float] = [1, 0]
        let exEmb: [Float]   = [1, 0]  // identical
        let embed: (String) -> [Float] = { _ in goldEmb }
        let gold = [LedgerExtraction.ExtractedFact(
            characterId: "Mia", fact: "is in flat.", certainty: .asserted, evidenceQuote: "q"
        )]
        let ex = [LedgerExtraction.ExtractedFact(
            characterId: "Miss Vance", fact: "is in flat.", certainty: .asserted, evidenceQuote: "q"
        )]
        // No alias → char mismatch → no TP
        let withoutAlias = LedgerExtraction.scoreByEmbedding(
            extracted: ex, gold: gold, embedding: { _ in goldEmb }, threshold: 0.7
        )
        try expectEqual(withoutAlias.truePositives, 0)
        // With alias → TP
        let withAlias = LedgerExtraction.scoreByEmbedding(
            extracted: ex, gold: gold,
            embedding: { _ in goldEmb }, threshold: 0.7,
            aliases: ["Miss Vance": "Mia"]
        )
        try expectEqual(withAlias.truePositives, 1)
        _ = exEmb; _ = embed
    }

    s.test("grammar can restrict certainty to a subset (asserted-only for Phase 4 #7)") {
        let g = LedgerExtraction.gbnfGrammar(certainties: [.asserted])
        try expectTrue(g.contains("asserted"), "asserted must be in restricted grammar")
        try expectFalse(g.contains("suspected"), "suspected must NOT appear in asserted-only grammar")
        try expectFalse(g.contains("mistaken"), "mistaken must NOT appear in asserted-only grammar")
    }

    s.test("grammar can restrict character_id to named bible characters + aliases") {
        let chars = [
            LedgerExtraction.CharacterRef(name: "Mia", aliases: ["Miss Vance"]),
            LedgerExtraction.CharacterRef(name: "Anders", aliases: []),
        ]
        let g = LedgerExtraction.gbnfGrammar(characters: chars)
        // The character_id rule is an alternation of GBNF-quoted
        // string literals: `"\"Mia\"" | "\"Miss Vance\"" | "\"Anders\""`.
        // In Swift-source: `"\\\"Mia\\\""`. Check by name presence
        // and alternation operator.
        try expectTrue(g.contains("Mia"), "Mia must appear in character_id alternation")
        try expectTrue(g.contains("Miss Vance"), "Miss Vance alias must appear")
        try expectTrue(g.contains("Anders"), "Anders must appear")
        try expectTrue(g.contains(" | "), "alternation operator must appear")
        // The GBNF-escaped form: `"\"Mia\""` written in Swift source as
        // `"\\\"Mia\\\""` — pin it to be sure the names are properly
        // wrapped as GBNF string literals.
        try expectTrue(g.contains("\\\"Mia\\\""), "Mia should be wrapped as GBNF string literal")
    }

    // MARK: - JSON Schema (Ollama / OpenAI-compat structured-output path)

    s.test("jsonSchema returns a top-level array schema with the ledger-fact object shape") {
        let schema = LedgerExtraction.jsonSchema()
        try expectEqual(schema["type"] as? String, "array")
        guard let items = schema["items"] as? [String: Any] else {
            throw TestFailure(message: "items missing", file: #file, line: #line)
        }
        try expectEqual(items["type"] as? String, "object")
        guard let props = items["properties"] as? [String: Any] else {
            throw TestFailure(message: "properties missing", file: #file, line: #line)
        }
        try expectTrue(props["character_id"] != nil, "character_id property missing")
        try expectTrue(props["fact"] != nil, "fact property missing")
        try expectTrue(props["certainty"] != nil, "certainty property missing")
        try expectTrue(props["evidence_quote"] != nil, "evidence_quote property missing")
        // All four fields must be required (Ollama / OpenAI strict mode).
        let required = items["required"] as? [String] ?? []
        try expectTrue(required.contains("character_id"))
        try expectTrue(required.contains("fact"))
        try expectTrue(required.contains("certainty"))
        try expectTrue(required.contains("evidence_quote"))
    }

    s.test("jsonSchema constrains certainty to the supplied subset") {
        let schema = LedgerExtraction.jsonSchema(certainties: [.asserted])
        let items = schema["items"] as? [String: Any] ?? [:]
        let props = items["properties"] as? [String: Any] ?? [:]
        let cert = props["certainty"] as? [String: Any] ?? [:]
        let certEnum = cert["enum"] as? [String] ?? []
        try expectEqual(certEnum, ["asserted"])
    }

    s.test("jsonSchema constrains character_id to bible names + aliases when supplied") {
        let chars = [
            LedgerExtraction.CharacterRef(name: "Mia", aliases: ["Miss Vance"]),
            LedgerExtraction.CharacterRef(name: "Anders", aliases: []),
        ]
        let schema = LedgerExtraction.jsonSchema(characters: chars)
        let items = schema["items"] as? [String: Any] ?? [:]
        let props = items["properties"] as? [String: Any] ?? [:]
        let cid = props["character_id"] as? [String: Any] ?? [:]
        let cidEnum = cid["enum"] as? [String] ?? []
        try expectTrue(cidEnum.contains("Mia"))
        try expectTrue(cidEnum.contains("Miss Vance"))
        try expectTrue(cidEnum.contains("Anders"))
    }

    s.test("grammar without characters falls back to free string for character_id (back-compat)") {
        let g = LedgerExtraction.gbnfGrammar()
        try expectTrue(
            g.contains("character_id"),
            "character_id field must exist"
        )
        // Without characters, the rule should reference `string`.
        try expectTrue(g.contains("string"), "fallback should use the string rule")
    }

    return s
}
