import Foundation

/// Continuity Audit (L10 — see `LOOM_CONTINUITY_AUDIT.md`) — the
/// pure-data layer for whole-manuscript contradiction detection.
///
/// The audit is a pipeline: per-scene typed-claim **extraction**
/// (LLM, schema-constrained) → deterministic fact-base diffing →
/// candidate-conflict retrieval → pairwise **adjudication** (LLM, one
/// claim pair at a time). This module owns the two LLM-facing ends —
/// prompt builders, JSON schemas, tolerant parsers — and the data
/// types they produce. Network orchestration lives elsewhere (the
/// `ContinuityAuditSpike` runner for Phase A); this stays test-pure,
/// the same split as `LedgerExtraction` vs. `LedgerSpike`.
public enum ContinuityAudit {

    // MARK: - Claim types

    /// The dimension a claim asserts something about. Each maps to one
    /// of the four audited contradiction classes (`attribute` and
    /// `event` both feed factual-drift detection).
    public enum ClaimType: String, Codable, Equatable, CaseIterable {
        case attribute
        case event
        case knowledgeState = "knowledge_state"
        case temporal
        case spatial
    }

    /// Where in the prose a claim was asserted. **Load-bearing for
    /// precision** — a claim sourced from `dialogue` or `thought` is
    /// the *character's* assertion, not a world-fact, so a lying
    /// character is not a continuity error.
    public enum ClaimSource: String, Codable, Equatable, CaseIterable {
        case narration
        case dialogue
        case thought
    }

    /// An atomic, decontextualised claim extracted from one scene.
    public struct Claim: Codable, Equatable {
        public var id: UUID
        public var type: ClaimType
        /// The entity the claim is about, as written (name or alias).
        public var subject: String
        /// For `attribute` claims, the normalised dimension
        /// ("eye colour", "occupation"); empty for other types.
        public var attributeKey: String
        /// The asserted value or proposition.
        public var value: String
        public var sourceSceneId: String
        public var source: ClaimSource
        /// Verbatim span the claim was grounded in.
        public var evidenceQuote: String

        public init(
            id: UUID = UUID(),
            type: ClaimType,
            subject: String,
            attributeKey: String,
            value: String,
            sourceSceneId: String,
            source: ClaimSource,
            evidenceQuote: String
        ) {
            self.id = id
            self.type = type
            self.subject = subject
            self.attributeKey = attributeKey
            self.value = value
            self.sourceSceneId = sourceSceneId
            self.source = source
            self.evidenceQuote = evidenceQuote
        }
    }

    public enum ParseError: Error {
        case noJSONArrayFound
        case noJSONObjectFound
        case malformedJSON
    }

    // MARK: - Extraction prompt

    /// Per-scene extraction instruction. Positive framing only — the
    /// `feedback_prompt_blacklist_evasion` lesson: enumerate what to
    /// produce, not what to avoid.
    public static let extractionInstruction = """
    You are auditing a novel for continuity. From the single scene below, extract every concrete, checkable claim — each as one atomic statement that stands on its own without the surrounding sentence.

    Each claim has a type:
    - attribute: a fixed trait of a person, place, or object (eye colour, a scar, a job, who owns what).
    - event: something that happened or that a character did or learned.
    - knowledge_state: a fact a character knows, believes, or refers to in this scene.
    - temporal: a time marker — a date, season, time of day, age, or how long since something.
    - spatial: a place fact — where something is, layout, distance, direction.

    Each claim has a source:
    - narration: stated by the narrator as fact.
    - dialogue: spoken aloud by a character.
    - thought: a character's private thought.

    Set subject to the person, place, or object the claim is about. For attribute claims set attribute_key to the dimension (for example "eye colour"); leave it empty otherwise. Set value to the claim itself. Set evidence_quote to a short verbatim span from the scene.
    """

    public static func buildExtractionPrompt(scenePose: String) -> String {
        return """
        \(extractionInstruction)

        Scene:
        \(scenePose)

        Claims (JSON array):
        """
    }

    /// JSON Schema for the extraction array — Ollama `format` /
    /// OpenAI strict mode. Constrains `type` and `source` to their
    /// enums so the model cannot invent dimensions.
    public static func extractionJSONSchema() -> [String: Any] {
        return [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "type": ["type": "string", "enum": ClaimType.allCases.map(\.rawValue)],
                    "subject": ["type": "string"],
                    "attribute_key": ["type": "string"],
                    "value": ["type": "string"],
                    "source": ["type": "string", "enum": ClaimSource.allCases.map(\.rawValue)],
                    "evidence_quote": ["type": "string"],
                ],
                "required": ["type", "subject", "attribute_key", "value", "source", "evidence_quote"],
            ],
        ]
    }

    // MARK: - Extraction parser

    private struct RawClaim: Decodable {
        let type: String?
        let subject: String?
        let attribute_key: String?
        let value: String?
        let source: String?
        let evidence_quote: String?
    }

    /// Parse the model's claim array. Tolerates chatty preamble /
    /// postamble and an unclosed array (per-object recovery), mirroring
    /// `LedgerExtraction.parseExtractedFacts`. Each parsed claim gets a
    /// fresh `id` and the supplied `sourceSceneId`; entries with an
    /// unknown `type` or `source` are dropped, valid siblings kept.
    public static func parseClaims(_ raw: String, sourceSceneId: String) throws -> [Claim] {
        guard let first = raw.firstIndex(of: "[") else {
            throw ParseError.noJSONArrayFound
        }

        func toClaims(_ items: [RawClaim]) -> [Claim] {
            items.compactMap { r -> Claim? in
                guard
                    let t = r.type, let type = ClaimType(rawValue: t),
                    let subject = r.subject,
                    let value = r.value,
                    let src = r.source, let source = ClaimSource(rawValue: src),
                    let quote = r.evidence_quote
                else { return nil }
                return Claim(
                    type: type,
                    subject: subject,
                    attributeKey: r.attribute_key ?? "",
                    value: value,
                    sourceSceneId: sourceSceneId,
                    source: source,
                    evidenceQuote: quote
                )
            }
        }

        // Strict path: a closed, well-formed array.
        if let last = raw.lastIndex(of: "]"), first <= last {
            let trimmed = String(raw[first...last])
            if let data = trimmed.data(using: .utf8),
               let items = try? JSONDecoder().decode([RawClaim].self, from: data) {
                return toClaims(items)
            }
        }

        // Fallback: walk top-level `{...}` blocks (brace depth, string-aware).
        let objects = topLevelObjects(in: raw, from: first)
        var collected: [Claim] = []
        for objText in objects {
            guard let data = objText.data(using: .utf8),
                  let item = try? JSONDecoder().decode(RawClaim.self, from: data)
            else { continue }
            collected.append(contentsOf: toClaims([item]))
        }
        if collected.isEmpty && objects.isEmpty {
            throw ParseError.malformedJSON
        }
        return collected
    }

    /// Extract each top-level `{...}` block starting at `from`. A
    /// brace-depth counter that ignores braces inside JSON strings.
    static func topLevelObjects(in raw: String, from: String.Index) -> [String] {
        var objects: [String] = []
        var depth = 0
        var inString = false
        var escape = false
        var start: String.Index? = nil
        var i = from
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
                    if depth == 0, let st = start {
                        objects.append(String(raw[st...i]))
                        start = nil
                    }
                }
            }
            i = raw.index(after: i)
        }
        return objects
    }
}
