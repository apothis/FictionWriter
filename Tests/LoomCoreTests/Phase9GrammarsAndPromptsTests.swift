import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — Stage A2 + Stage D grammars,
/// schemas, prompts, and parsers. LOOM_ENTITY_DISCOVERY_SPIKE §3.1.
///
/// Stage A2 (candidate generation): scene prose → list of candidate
///   entity mentions with surface form + kind + first-seen quote.
/// Stage D (normalisation): single candidate + scene context →
///   structured entity tuple (canonical_name, aliases, one_line,
///   evidence_quote).
///
/// Both stages ship GBNF (kobold) + JSON Schema (Ollama) variants
/// — same shape, two encodings — plus a prompt builder per stage
/// and a tolerant parser that handles truncation / preamble noise
/// in the same style as `LedgerExtraction.parseExtractedFacts`.
func phase9GrammarsAndPromptsTests() -> TestSuite {
    let s = TestSuite("Phase9GrammarsAndPrompts")

    // MARK: - Stage A2 grammar

    s.test("Stage A2 GBNF: emits root → array of candidates") {
        // GBNF escapes its inner quotes (the rendered grammar
        // string contains `\"surface\":` not `"surface":`), so we
        // just check the field-name tokens are present.
        let g = EntityDiscovery.candidateGenerationGBNF()
        try expectTrue(g.contains("root ::="))
        try expectTrue(g.contains("candidate ::="))
        try expectTrue(g.contains("surface"))
        try expectTrue(g.contains("kind"))
        try expectTrue(g.contains("first_seen_quote"))
    }

    s.test("Stage A2 GBNF: kind alternation has both character and place") {
        let g = EntityDiscovery.candidateGenerationGBNF()
        try expectTrue(g.contains("character"))
        try expectTrue(g.contains("place"))
    }

    s.test("Stage A2 GBNF: ws is constrained to single optional space (empirical guard)") {
        // Per LedgerExtraction's hard-won lesson: ws ::= [ \t\n\r]*
        // lets the model stall in degenerate whitespace. Keep tight.
        let g = EntityDiscovery.candidateGenerationGBNF()
        try expectTrue(g.contains("ws ::= \" \"?"))
        try expectFalse(g.contains("ws ::= [ \\t\\n\\r]*"))
    }

    s.test("Stage A2 GBNF: facts kept on one line (kobold v1.111 multi-line bug)") {
        let g = EntityDiscovery.candidateGenerationGBNF()
        // The `candidate ::=` rule must not span multiple lines.
        for line in g.split(separator: "\n") {
            if line.contains("candidate ::=") {
                try expectFalse(line.contains("\\\n"))
            }
        }
    }

    s.test("Stage A2 JSON Schema: array-of-objects shape") {
        let schema = EntityDiscovery.candidateGenerationJSONSchema()
        try expectEqual(schema["type"] as? String, "array")
        let items = try expectNotNil(schema["items"] as? [String: Any])
        try expectEqual(items["type"] as? String, "object")
        let props = try expectNotNil(items["properties"] as? [String: Any])
        try expectTrue(props["surface"] != nil)
        try expectTrue(props["kind"] != nil)
        try expectTrue(props["first_seen_quote"] != nil)
        let kind = try expectNotNil(props["kind"] as? [String: Any])
        let enum_ = try expectNotNil(kind["enum"] as? [String])
        try expectEqual(Set(enum_), Set(["character", "place", "object"]))
    }

    // MARK: - Stage A2 prompt

    s.test("Stage A2 prompt: includes scene prose verbatim") {
        let prose = "Mia opened the door. Anders was standing there."
        let prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: prose,
            knownEntityNames: ["Mia"]
        )
        try expectTrue(prompt.contains(prose))
    }

    s.test("Stage A2 prompt: enumerates known entities so model skips them") {
        let prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: "...",
            knownEntityNames: ["Mia", "Anders", "Karim"]
        )
        try expectTrue(prompt.contains("Mia"))
        try expectTrue(prompt.contains("Anders"))
        try expectTrue(prompt.contains("Karim"))
    }

    s.test("Stage A2 prompt: instructs proper-noun-only (mirrors §4.3 gate)") {
        let prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: "...", knownEntityNames: []
        )
        // Must contain some form of "proper noun" guidance so the
        // model's behaviour matches the gate's behaviour.
        try expectTrue(prompt.lowercased().contains("proper noun"))
    }

    s.test("Stage A2 prompt: works with empty known-entities list (cold start)") {
        let prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: "Scene prose.", knownEntityNames: []
        )
        try expectTrue(prompt.contains("Scene prose."))
    }

    s.test("Stage A2 instruction: no 'new' qualifier (live-smoke recall bug)") {
        // Live-smoke: with an empty known-list, "Identify new
        // characters…" made gemma4_2b emit only the narratively-
        // newest character (one spoken-about in dialogue) and skip
        // the two acting protagonists. Dedup against the bible is
        // the known-list line's job, not a word in the instruction.
        let instr = EntityDiscovery.candidateGenerationPromptInstruction.lowercased()
        try expectFalse(instr.contains("new character"),
                        "'new' makes the model scope to narrative recency")
        try expectFalse(instr.contains("identify new"),
                        "'new' makes the model scope to narrative recency")
        // Positive framing: ask for the full cast.
        try expectTrue(instr.contains("every character"),
                       "instruction should ask for every character")
    }

    s.test("Stage A2 instruction: explicitly includes spoken-about characters") {
        // The recall miss was asymmetric — the model kept the
        // spoken-about character and dropped the present ones. Be
        // explicit that both count so neither side is privileged.
        let instr = EntityDiscovery.candidateGenerationPromptInstruction.lowercased()
        try expectTrue(instr.contains("spoken about"),
                       "instruction must name the spoken-about case")
    }

    // MARK: - Stage A2 parser

    s.test("Stage A2 parser: clean JSON array decodes") {
        let raw = """
        [
          {"surface": "Anders", "kind": "character", "first_seen_quote": "Anders. I'm meant to be at a dinner."},
          {"surface": "The Quay", "kind": "place", "first_seen_quote": "The pub was called The Quay"}
        ]
        """
        let cands = try EntityDiscovery.parseCandidates(raw)
        try expectEqual(cands.count, 2)
        try expectEqual(cands[0].surface, "Anders")
        try expectEqual(cands[0].kind, .character)
        try expectEqual(cands[1].kind, .place)
    }

    s.test("Stage A2 parser: tolerates preamble / postamble") {
        let raw = "Sure, here you go:\n[{\"surface\": \"Anders\", \"kind\": \"character\", \"first_seen_quote\": \"x\"}]\nDone."
        let cands = try EntityDiscovery.parseCandidates(raw)
        try expectEqual(cands.count, 1)
        try expectEqual(cands[0].surface, "Anders")
    }

    s.test("Stage A2 parser: empty array → empty result (not an error)") {
        let cands = try EntityDiscovery.parseCandidates("[]")
        try expectEqual(cands.count, 0)
    }

    s.test("Stage A2 parser: throws on no array found") {
        do {
            _ = try EntityDiscovery.parseCandidates("not json at all")
            throw TestFailure(message: "expected throw", file: #file, line: #line)
        } catch EntityDiscovery.ParseError.noJSONArrayFound {
            // ok
        }
    }

    s.test("Stage A2 parser: skips malformed entries inside array (truncation recovery)") {
        // Mid-emit truncation: first object complete, second is
        // half-written.
        let raw = "[{\"surface\": \"Anders\", \"kind\": \"character\", \"first_seen_quote\": \"a\"}, {\"surface\": \"Theo\""
        let cands = try EntityDiscovery.parseCandidates(raw)
        // At minimum the complete first object should survive.
        try expectTrue(cands.contains(where: { $0.surface == "Anders" }))
    }

    // MARK: - Stage D grammar

    s.test("Stage D GBNF: emits root → single normalised entity object") {
        let g = EntityDiscovery.normalisationGBNF()
        try expectTrue(g.contains("root ::="))
        try expectTrue(g.contains("kind"))
        try expectTrue(g.contains("canonical_name"))
        try expectTrue(g.contains("aliases"))
        try expectTrue(g.contains("one_line"))
        try expectTrue(g.contains("evidence_quote"))
    }

    s.test("Stage D GBNF: aliases is an array-of-strings") {
        let g = EntityDiscovery.normalisationGBNF()
        try expectTrue(g.contains("aliases ::="))
    }

    s.test("Stage D GBNF: same empirical-guard ws") {
        let g = EntityDiscovery.normalisationGBNF()
        try expectTrue(g.contains("ws ::= \" \"?"))
    }

    s.test("Stage D JSON Schema: object shape with required fields") {
        let schema = EntityDiscovery.normalisationJSONSchema()
        try expectEqual(schema["type"] as? String, "object")
        let props = try expectNotNil(schema["properties"] as? [String: Any])
        try expectTrue(props["kind"] != nil)
        try expectTrue(props["canonical_name"] != nil)
        try expectTrue(props["aliases"] != nil)
        try expectTrue(props["one_line"] != nil)
        try expectTrue(props["evidence_quote"] != nil)
        let required = try expectNotNil(schema["required"] as? [String])
        try expectTrue(required.contains("kind"))
        try expectTrue(required.contains("canonical_name"))
    }

    // MARK: - Stage D prompt

    s.test("Stage D prompt: includes candidate surface + kind + scene prose") {
        let prompt = EntityDiscovery.buildNormalisationPrompt(
            candidateSurface: "Dr Thorn",
            candidateKind: .character,
            firstSeenQuote: "Dr Thorn arrived at my flat",
            scenePose: "Scene about Dr Thorn..."
        )
        try expectTrue(prompt.contains("Dr Thorn"))
        try expectTrue(prompt.contains("character"))
        try expectTrue(prompt.contains("Scene about Dr Thorn..."))
    }

    s.test("Stage D prompt: instructs canonical=most-formal name") {
        let prompt = EntityDiscovery.buildNormalisationPrompt(
            candidateSurface: "Marius",
            candidateKind: .character,
            firstSeenQuote: "x",
            scenePose: "x"
        )
        // Must direct the model to prefer the full-form name.
        let lower = prompt.lowercased()
        try expectTrue(lower.contains("canonical") || lower.contains("most complete"))
    }

    // MARK: - Stage D parser

    s.test("Stage D parser: clean JSON object decodes") {
        let raw = """
        {
          "kind": "character",
          "canonical_name": "Marius Thorn",
          "aliases": ["Dr Thorn", "Thorn", "Marius"],
          "one_line": "A doctor who made a house call.",
          "evidence_quote": "Dr Thorn arrived at my flat."
        }
        """
        let ent = try EntityDiscovery.parseNormalisedEntity(raw)
        try expectEqual(ent.kind, .character)
        try expectEqual(ent.canonicalName, "Marius Thorn")
        try expectEqual(ent.aliases, ["Dr Thorn", "Thorn", "Marius"])
        try expectEqual(ent.oneLine, "A doctor who made a house call.")
        try expectTrue(ent.evidenceQuote.contains("Dr Thorn arrived"))
    }

    s.test("Stage D parser: tolerates preamble") {
        let raw = "Here's the normalised entry:\n{\"kind\": \"place\", \"canonical_name\": \"The Quay\", \"aliases\": [], \"one_line\": \"A pub.\", \"evidence_quote\": \"x\"}\n"
        let ent = try EntityDiscovery.parseNormalisedEntity(raw)
        try expectEqual(ent.kind, .place)
        try expectEqual(ent.canonicalName, "The Quay")
    }

    s.test("Stage D parser: throws on no object found") {
        do {
            _ = try EntityDiscovery.parseNormalisedEntity("nope")
            throw TestFailure(message: "expected throw", file: #file, line: #line)
        } catch EntityDiscovery.ParseError.noJSONObjectFound {
            // ok
        }
    }

    return s
}
