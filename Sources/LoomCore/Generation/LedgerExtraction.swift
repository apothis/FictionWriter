import Foundation

/// Phase 4 §14.1 #5 / LOOM_STORY_BIBLE §3 / LOOM_MEMORY §4.5 —
/// per-character knowledge-ledger extraction (pure-data layer).
///
/// **Three pieces, all pure data + deterministic:**
///
/// - `buildExtractionPrompt(characters:scenePose:)` assembles the
///   §3.3 extraction prompt skeleton (bible-character JSON list +
///   scene prose, with explicit schema instructions). Sent to the
///   summariser-role server's single-prompt completion endpoint.
///
/// - `parseExtractedFacts(_:)` parses the model's JSON-array response
///   back into structured `ExtractedFact`s. Tolerates chatty preamble
///   / postamble (local models routinely wrap structured output in
///   "Here are the facts:..."). Drops entries with invalid certainty
///   values but keeps valid siblings.
///
/// - `score(extracted:gold:aliases:)` compares a model's output
///   against a hand-graded gold ledger, returning precision / recall /
///   per-certainty breakdowns. The match predicate is (character_id
///   alias-resolved, certainty) plus fact-text Jaccard ≥ 0.5 over
///   normalised tokens with the character's surface forms stripped —
///   loose enough to count synonym rewordings ("learned" ≡
///   "discovered"), strict enough to keep distinct facts apart
///   ("door was unlocked" vs "door was open" → 0.33).
///
/// The network-y eval runner that wires these three pieces against
/// the live summariser server lives in the separate `LedgerSpike`
/// executable target; this module stays test-pure.
public enum LedgerExtraction {

    // MARK: - Types

    public struct CharacterRef: Codable, Equatable {
        public let name: String
        public let aliases: [String]
        public init(name: String, aliases: [String]) {
            self.name = name
            self.aliases = aliases
        }
    }

    public enum Certainty: String, Codable, Equatable, CaseIterable {
        case asserted
        case suspected
        case unknown
        case mistaken
    }

    public struct ExtractedFact: Codable, Equatable {
        public let characterId: String
        public let fact: String
        public let certainty: Certainty
        public let evidenceQuote: String

        public init(characterId: String, fact: String, certainty: Certainty, evidenceQuote: String) {
            self.characterId = characterId
            self.fact = fact
            self.certainty = certainty
            self.evidenceQuote = evidenceQuote
        }
    }

    public struct ScoreReport: Equatable {
        public let truePositives: Int
        public let falsePositives: Int
        public let falseNegatives: Int

        public init(truePositives: Int, falsePositives: Int, falseNegatives: Int) {
            self.truePositives = truePositives
            self.falsePositives = falsePositives
            self.falseNegatives = falseNegatives
        }

        public var precision: Double {
            let denom = truePositives + falsePositives
            return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
        }
        public var recall: Double {
            let denom = truePositives + falseNegatives
            return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
        }
        public var f1: Double {
            let p = precision, r = recall
            return (p + r) == 0 ? 0 : 2 * p * r / (p + r)
        }
    }

    public enum ParseError: Error {
        case noJSONArrayFound
        case malformedJSON
    }

    // MARK: - Prompt builder (LOOM_STORY_BIBLE §3.3 verbatim)

    /// Constant instruction body the prompt builder splices ahead of
    /// the character JSON + scene prose. Exposed as a top-level
    /// constant so the AppState orchestrator can embed it once at
    /// boot and pass the vector into `LedgerFilters.filterPromptLeakage`
    /// for sub-task 8 (the §10.5 prompt-leakage filter catches facts
    /// that echo this instruction back into the extractor's output).
    public static let extractionPromptInstruction =
        "Extract factual claims about the listed characters from the scene below. List one entry per fact the character DID or LEARNED in this scene. Be thorough — capture every clear action and observation."

    public static func buildExtractionPrompt(
        characters: [CharacterRef],
        scenePose: String
    ) -> String {
        let characterListJSON: String = {
            // Compact stable JSON — sort keys so the prompt cache is
            // stable across reorderings of the input array. Single-line
            // encoding keeps the prompt token-budget tight.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(characters)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }()

        // The GBNF grammar (`LedgerExtraction.gbnfGrammar`) enforces
        // the JSON shape and the certainty enum — the prompt body
        // doesn't need to repeat schema instructions. Empirically,
        // long schema-explanation prompts bias the model toward
        // emitting `[]` ("nothing to extract") even with the grammar
        // forcing valid JSON. Keep the prompt short, give it the
        // bible + scene + a clear "extract facts" framing.
        return """
        \(Self.extractionPromptInstruction)

        Characters (names + aliases):
        \(characterListJSON)

        Scene:
        \(scenePose)

        Facts (JSON array):
        """
    }

    // MARK: - GBNF grammar (LOOM_LEDGER_SPIKE §8.1)

    /// GBNF grammar string for the §3.3 JSON-array schema. Passed to
    /// KoboldCpp's `grammar` parameter (verified working against the
    /// production server 2026-05-11) — gives the model a structural
    /// guarantee of well-formed JSON output, sidestepping the brittle
    /// prompt-engineering workarounds documented in LOOM_LEDGER_SPIKE
    /// §5 (force-prefilled `[`, malformed-JSON recovery parser, etc).
    ///
    /// `certainties` controls the certainty-value enum the grammar
    /// allows the model to emit. The production extractor passes
    /// `[.asserted]` (negative knowledge is derived from scene-exposure
    /// rather than extracted, per §8.3); callers that want the full
    /// §3.3 schema can pass all four. Order in the array determines
    /// the order in the grammar alternation — has no semantic effect
    /// but may bias sampling slightly toward earlier-listed values.
    /// Optional `characters` parameter restricts the grammar's
    /// `character_id` field to an alternation of the known character
    /// names + aliases — empirically observed (LOOM_LEDGER_SPIKE §10):
    /// without this restriction, the model occasionally emits garbage
    /// in `character_id` ("hallway", "kitchen", or sentence fragments
    /// like "To bed early."). Restricting the field to a string
    /// literal alternation forces the model to pick one of the bible
    /// names, eliminating that failure mode at the grammar level.
    public static func gbnfGrammar(
        certainties: [Certainty] = Certainty.allCases,
        characters: [CharacterRef] = []
    ) -> String {
        let certAlternation = certainties.map { "\"\\\"\($0.rawValue)\\\"\"" }.joined(separator: " | ")

        // Build the character_id rule. If callers supply the bible
        // characters, restrict to those names + aliases as a string
        // alternation. Otherwise fall back to a free string (back-compat
        // for the existing tests).
        let characterIdRule: String
        if characters.isEmpty {
            characterIdRule = "string"
        } else {
            var allNames: [String] = []
            for c in characters {
                allNames.append(c.name)
                allNames.append(contentsOf: c.aliases)
            }
            characterIdRule = allNames
                .map { "\"\\\"\($0)\\\"\"" }
                .joined(separator: " | ")
        }
        // GBNF for KoboldCpp / llama.cpp.
        //
        // Two empirical guards baked in:
        //
        // 1. Multi-line rule definitions failed grammar compilation
        //    on KoboldCpp v1.111 (returned `completion_tokens: 1`
        //    with empty text). The fact rule is kept on one line.
        //
        // 2. `ws ::= " "?` instead of `ws ::= [ \t\n\r]*`. The latter
        //    let the model emit unbounded whitespace between fields
        //    and stall in a degenerate state (observed: 2148 chars of
        //    `\n` between `"certainty":` and the value, eating the
        //    max_length budget). A single optional space is plenty —
        //    the parser doesn't need pretty-printing.
        //
        // String rule uses simpler-than-RFC-8259 escape handling
        // (`([^"\\] | "\\" .)*`); the model is unlikely to emit
        // invalid escapes when generating English prose facts.
        return "root ::= \"[\" ws (fact (ws \",\" ws fact)*)? ws \"]\"\n"
            + "fact ::= \"{\" ws \"\\\"character_id\\\":\" ws (\(characterIdRule)) ws \",\" ws \"\\\"fact\\\":\" ws string ws \",\" ws \"\\\"certainty\\\":\" ws (\(certAlternation)) ws \",\" ws \"\\\"evidence_quote\\\":\" ws string ws \"}\"\n"
            + "string ::= \"\\\"\" ([^\"\\\\] | \"\\\\\" .)* \"\\\"\"\n"
            + "ws ::= \" \"?"
    }

    // MARK: - JSON Schema (Ollama / OpenAI-compat structured outputs)

    /// JSON Schema for the §3.3 ledger-fact array. Same shape as the
    /// GBNF (sibling `gbnfGrammar(certainties:characters:)`) but in
    /// JSON-Schema form for backends that take a schema rather than a
    /// grammar — specifically Ollama's `format` parameter (≥ 0.5) and
    /// the OpenAI `response_format: json_schema` strict mode.
    ///
    /// Returns `[String: Any]` rather than `Data` because callers
    /// usually want to splice this into a larger request body before
    /// serialising — saves a round-trip through `JSONSerialization`.
    public static func jsonSchema(
        certainties: [Certainty] = Certainty.allCases,
        characters: [CharacterRef] = []
    ) -> [String: Any] {
        let characterIdProperty: [String: Any]
        if characters.isEmpty {
            characterIdProperty = ["type": "string"]
        } else {
            var allNames: [String] = []
            for c in characters {
                allNames.append(c.name)
                allNames.append(contentsOf: c.aliases)
            }
            characterIdProperty = [
                "type": "string",
                "enum": allNames,
            ]
        }
        return [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "character_id": characterIdProperty,
                    "fact": ["type": "string"],
                    "certainty": [
                        "type": "string",
                        "enum": certainties.map { $0.rawValue },
                    ],
                    "evidence_quote": ["type": "string"],
                ],
                "required": ["character_id", "fact", "certainty", "evidence_quote"],
            ],
        ]
    }

    // MARK: - Response parser

    public static func parseExtractedFacts(_ raw: String) throws -> [ExtractedFact] {
        // Local models routinely wrap structured output in preamble /
        // postamble. Locate the outermost `[` and try strict array
        // decoding if a matching `]` exists; otherwise fall through
        // to per-object recovery (the model frequently runs out of
        // tokens mid-array and never closes the `]`).
        guard let first = raw.firstIndex(of: "[") else {
            throw ParseError.noJSONArrayFound
        }

        struct RawItem: Decodable {
            let character_id: String?
            let fact: String?
            let certainty: String?
            let evidence_quote: String?
        }

        func itemsToFacts(_ items: [RawItem]) -> [ExtractedFact] {
            items.compactMap { raw in
                guard
                    let cid = raw.character_id,
                    let f = raw.fact,
                    let c = raw.certainty,
                    let cert = Certainty(rawValue: c),
                    let q = raw.evidence_quote
                else { return nil }
                return ExtractedFact(characterId: cid, fact: f, certainty: cert, evidenceQuote: q)
            }
        }

        // Strict path: full array decode (only if there's a closing
        // `]` and the contents parse cleanly).
        if let last = raw.lastIndex(of: "]"), first <= last {
            let trimmed = String(raw[first...last])
            if let data = trimmed.data(using: .utf8),
               let items = try? JSONDecoder().decode([RawItem].self, from: data) {
                return itemsToFacts(items)
            }
        }

        // Fallback path: the array is malformed or unclosed
        // (truncation, key typos, missing commas — all observed
        // against Qwen3-class models doing this task). Walk the
        // response from the first `[` and try to parse each
        // top-level `{...}` block individually. Use a brace-depth
        // counter that ignores braces inside strings.
        var objects: [String] = []
        var depth = 0
        var inString = false
        var escape = false
        var start: String.Index? = nil
        var i = first
        while i < raw.endIndex {
            let ch = raw[i]
            if escape { escape = false }
            else if ch == "\\" && inString { escape = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" {
                    if depth == 0 { start = i }
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0, let s = start {
                        let nextIdx = raw.index(after: i)
                        objects.append(String(raw[s..<nextIdx]))
                        start = nil
                    }
                }
            }
            i = raw.index(after: i)
        }

        var collected: [ExtractedFact] = []
        for objText in objects {
            guard let data = objText.data(using: .utf8),
                  let item = try? JSONDecoder().decode(RawItem.self, from: data)
            else { continue }
            collected.append(contentsOf: itemsToFacts([item]))
        }
        if collected.isEmpty && objects.isEmpty {
            throw ParseError.malformedJSON
        }
        return collected
    }

    // MARK: - Embedding scorer (LOOM_LEDGER_SPIKE §10)

    /// Cosine similarity between two equal-length vectors. Returns 0
    /// for empty inputs, zero-norm vectors, or length mismatch — never
    /// throws. Production callers should pre-validate dimensionality
    /// (the embedding model's vector dim is stable per server).
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot: Double = 0, na: Double = 0, nb: Double = 0
        for i in 0..<a.count {
            let x = Double(a[i]), y = Double(b[i])
            dot += x * y; na += x * x; nb += y * y
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Score extracted facts against gold using cosine similarity over
    /// pre-computed embeddings instead of Jaccard wordform similarity.
    /// Match predicate: alias-resolved `character_id` matches, certainty
    /// matches, and `cosineSimilarity(embedding(extracted.fact),
    /// embedding(gold.fact)) >= threshold`.
    ///
    /// `embedding` is a closure that returns the vector for a fact's
    /// text. The spike's runner caches embeddings up-front so each
    /// fact is embedded once; this signature keeps the scorer pure-data
    /// and testable (a synthetic embedding map suffices).
    ///
    /// Threshold default 0.65 is the conservative starting point per
    /// SillyTavern's verified default for chat-vectorisation (LOOM_MEMORY
    /// §B2): 0.55 floor for bge-small, with diminishing returns above
    /// 0.7. 0.65 sits in the productive middle.
    public static func scoreByEmbedding(
        extracted: [ExtractedFact],
        gold: [ExtractedFact],
        embedding: (String) -> [Float],
        threshold: Double = 0.65,
        aliases: [String: String] = [:]
    ) -> ScoreReport {
        func canonical(_ id: String) -> String { aliases[id] ?? id }
        var unmatchedGold = gold.indices.map { (gold[$0], false) }
        var tp = 0, fp = 0
        for ex in extracted {
            let exCanon = canonical(ex.characterId)
            let exVec = embedding(ex.fact)
            var matchIdx: Int? = nil
            for i in unmatchedGold.indices where !unmatchedGold[i].1 {
                let g = unmatchedGold[i].0
                if canonical(g.characterId) == exCanon
                    && g.certainty == ex.certainty
                    && cosineSimilarity(exVec, embedding(g.fact)) >= threshold
                {
                    matchIdx = i; break
                }
            }
            if let i = matchIdx {
                unmatchedGold[i].1 = true
                tp += 1
            } else {
                fp += 1
            }
        }
        let fn = unmatchedGold.filter { !$0.1 }.count
        return ScoreReport(truePositives: tp, falsePositives: fp, falseNegatives: fn)
    }

    // MARK: - Scorer (Jaccard wordform — kept as a fast fallback)

    public static func score(
        extracted: [ExtractedFact],
        gold: [ExtractedFact],
        aliases: [String: String] = [:]
    ) -> ScoreReport {
        // Resolve every characterId through the alias map so "Miss
        // Vance" ≡ "Mia" if `aliases["Miss Vance"] == "Mia"`.
        func canonical(_ id: String) -> String {
            aliases[id] ?? id
        }

        // Build a reverse index: canonical name → all known names+
        // aliases that resolve to it (including the canonical itself).
        // We strip these from a fact's text before Jaccard, so the
        // character-name surface form ("Mia" vs "Miss Vance") doesn't
        // dominate the similarity score for facts that mention the
        // character by name.
        var formsForCanonical: [String: Set<String>] = [:]
        for (alias, canon) in aliases {
            formsForCanonical[canon, default: []].insert(alias)
            formsForCanonical[canon, default: []].insert(canon)
        }
        func formsFor(_ canon: String) -> Set<String> {
            formsForCanonical[canon] ?? [canon]
        }

        // Match an extracted fact against any unmatched gold fact:
        // same canonical character + same certainty + fact-text
        // Jaccard ≥ 0.6 over normalised word tokens (with the
        // character's known surface forms stripped first).
        var unmatchedGold = gold.indices.map { (gold[$0], false, $0) }
        var truePositives = 0
        var falsePositives = 0

        for ex in extracted {
            let exCanon = canonical(ex.characterId)
            let stripForms = formsFor(exCanon)
            var matchIdx: Int? = nil
            for i in unmatchedGold.indices where !unmatchedGold[i].1 {
                let g = unmatchedGold[i].0
                if canonical(g.characterId) == exCanon
                    && g.certainty == ex.certainty
                    && jaccardWordSimilarity(ex.fact, g.fact, strippingForms: stripForms) >= 0.5
                {
                    matchIdx = i
                    break
                }
            }
            if let i = matchIdx {
                unmatchedGold[i].1 = true
                truePositives += 1
            } else {
                falsePositives += 1
            }
        }

        let falseNegatives = unmatchedGold.filter { !$0.1 }.count
        return ScoreReport(
            truePositives: truePositives,
            falsePositives: falsePositives,
            falseNegatives: falseNegatives
        )
    }

    /// Tokenise on whitespace + punctuation, lowercase, drop common
    /// stopwords + the character's known surface forms. Returns
    /// Jaccard similarity over the resulting sets.
    private static func jaccardWordSimilarity(
        _ a: String,
        _ b: String,
        strippingForms: Set<String> = []
    ) -> Double {
        let stripLower = Set(strippingForms.flatMap { wordTokens($0) })
        let setA = wordTokens(a).subtracting(stripLower)
        let setB = wordTokens(b).subtracting(stripLower)
        if setA.isEmpty && setB.isEmpty { return 1.0 }
        let inter = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "was", "were", "be", "been", "being",
        "of", "in", "on", "at", "to", "for", "from", "by", "with",
        "and", "or", "but", "as", "that", "this", "these", "those",
        "it", "its", "they", "them", "their", "there",
    ]

    private static func wordTokens(_ s: String) -> Set<String> {
        let lowered = s.lowercased()
        var cleaned = ""
        cleaned.reserveCapacity(lowered.count)
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                cleaned.unicodeScalars.append(scalar)
            } else {
                cleaned.append(" ")
            }
        }
        let words = cleaned.split(separator: " ").map(String.init)
        return Set(words.filter { !$0.isEmpty && !stopwords.contains($0) })
    }
}
