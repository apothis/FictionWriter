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

    public enum Certainty: String, Codable, Equatable {
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

        // Two load-bearing tail elements:
        //
        // 1. `JSON output:\n[` force-prefill — without the `[`, Qwen-
        //    class base models reading the §3.3 prompt verbatim treat
        //    the scene prose as document-complete and emit EOS
        //    immediately (observed: completion_tokens=1, empty text).
        //    Starting the prompt inside a JSON array forces the model
        //    to continue the structure.
        //
        // 2. The downstream parser already handles preamble/postamble
        //    and anchors on the outermost `[`/`]`, so the synthesized
        //    leading `[` doesn't need to be stripped here.
        return """
        Read the scene below. Extract factual claims about characters present in or referenced by the scene. For each fact, output a JSON object with:
        - character_id: which character this fact is about (use NAME or ALIAS).
        - fact: natural-language assertion (one sentence, third-person).
        - certainty: "asserted" if shown clearly, "suspected" if hinted, "unknown" if explicitly NOT known by this character, "mistaken" if the character holds a wrong belief.
        - evidence_quote: short quote from the scene supporting the assertion.

        Distinguish what the character DID or LEARNED in this scene from what was already true.
        Do not infer beyond the text. Do not invent.
        Output a JSON array. Empty array if no claims extractable.

        Bible characters (names + aliases):
        \(characterListJSON)

        Scene:
        \(scenePose)

        JSON output:
        [
        """
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

    // MARK: - Scorer

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
