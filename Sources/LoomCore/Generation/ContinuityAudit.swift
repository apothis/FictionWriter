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
        case noJSONObjectFound
        case malformedJSON
    }

    // MARK: - Extraction prompt

    /// Per-scene extraction instruction.
    ///
    /// Output is **JSONL** — one flat JSON object per line, no array.
    /// The instruction pins the six field names and the allowed enum
    /// values *in the prompt* rather than relying on a `format` schema:
    /// Ollama's schema-constrained sampling flakes ~50% on gemma4_2b
    /// (degenerate non-terminating buffer → empty content; HANDOFF
    /// §15.19, commits `b6c7a97` / `d4df07e`). The extractor therefore
    /// runs unconstrained and `parseClaims` is tolerant.
    ///
    /// Positive framing only — the `feedback_prompt_blacklist_evasion`
    /// lesson: enumerate what to produce, not what to avoid.
    public static let extractionInstruction = """
    You are auditing a novel for continuity. From the single scene below, extract every concrete, checkable claim — each as one atomic statement that stands on its own without the surrounding sentence.

    Output one JSON object per line (JSONL) — no surrounding array, no commentary, no blank lines. Each object has exactly these six keys:

    - "type": one of attribute, event, knowledge_state, temporal, spatial.
        attribute = a fixed trait of a person, place, or object (eye colour, a scar, a job, who owns what).
        event = something that happened or that a character did or learned.
        knowledge_state = a fact a character knows, believes, or refers to in this scene.
        temporal = a time marker (a date, season, time of day, age, or how long since something).
        spatial = a place fact (where something is, layout, distance, direction).
    - "subject": the person, place, or object the claim is about.
    - "attribute_key": for an attribute claim, the dimension (for example "eye colour"); an empty string otherwise.
    - "value": the claim itself, as one self-contained statement.
    - "source": one of narration (stated by the narrator as fact), dialogue (spoken aloud by a character), thought (a character's private thought).
    - "evidence_quote": a short verbatim span copied from the scene.
    """

    public static func buildExtractionPrompt(scenePose: String) -> String {
        return """
        \(extractionInstruction)

        Scene:
        \(scenePose)

        Claims (one JSON object per line):
        """
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

    /// Parse the model's claims. Format-agnostic: works on a JSON
    /// array, on JSONL (one object per line — the production format),
    /// and through chatty preamble / postamble, by walking every
    /// top-level `{...}` block. Each parsed claim gets a fresh `id` and
    /// the supplied `sourceSceneId`; entries with an unknown `type` or
    /// `source` are dropped, valid siblings kept. Throws only when the
    /// response contains no JSON object at all.
    public static func parseClaims(_ raw: String, sourceSceneId: String) throws -> [Claim] {
        guard let first = raw.firstIndex(of: "{") else {
            throw ParseError.noJSONObjectFound
        }
        var collected: [Claim] = []
        for objText in topLevelObjects(in: raw, from: first) {
            guard let data = objText.data(using: .utf8),
                  let r = try? JSONDecoder().decode(RawClaim.self, from: data)
            else { continue }
            guard
                let t = r.type, let type = ClaimType(rawValue: t),
                let subject = r.subject,
                let value = r.value,
                let src = r.source, let source = ClaimSource(rawValue: src),
                let quote = r.evidence_quote
            else { continue }
            collected.append(Claim(
                type: type,
                subject: subject,
                attributeKey: r.attribute_key ?? "",
                value: value,
                sourceSceneId: sourceSceneId,
                source: source,
                evidenceQuote: quote
            ))
        }
        return collected
    }

    // MARK: - Type-classification stage

    /// Re-classify extracted claims in a focused, scene-scoped pass.
    ///
    /// The Goetia/gemma A/B (HANDOFF §15.37 addendum) showed a bigger
    /// model lifts *content* recall but not *type* accuracy — typing
    /// is overloaded when one call also does recall, JSON shape, and
    /// quoting (the Claimify finding). Extraction therefore emits a
    /// best-effort type, and this stage re-decides it with a call that
    /// does nothing else: scene + the claim list → one type per claim.
    public static func buildTypingPrompt(scenePose: String, claims: [Claim]) -> String {
        let numbered = claims.enumerated()
            .map { "\($0.offset + 1). \($0.element.value)" }
            .joined(separator: "\n")
        return """
        You are auditing a novel for continuity. Below is a scene and a numbered list of claims already extracted from it. Decide the single best type for each claim.

        - attribute: a fixed trait of a person, place, or object (eye colour, a scar, a job, who owns what).
        - event: something that happened or that a character did or learned.
        - knowledge_state: a fact a character knows, believes, or refers to.
        - temporal: a time marker (a date, season, time of day, age, or how long since something).
        - spatial: a place fact (where something is, layout, distance, direction).

        Scene:
        \(scenePose)

        Claims:
        \(numbered)

        For each claim output one line, exactly "<number>. <type>", and nothing else.
        """
    }

    /// Parse the typing pass into a `claimIndex (zero-based) → type`
    /// map. Tolerant of preamble and assorted `1.` / `1)` / `1:`
    /// separators; an unknown type or out-of-range index is dropped.
    public static func parseTypes(_ raw: String, count: Int) -> [Int: ClaimType] {
        var out: [Int: ClaimType] = [:]
        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // leading number
            let digits = trimmed.prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(digits), n >= 1, n <= count else { continue }
            // the type token — last run of letters/underscores on the line
            let rest = trimmed.drop { $0.isNumber }
                .drop { ".:)- \t".contains($0) }
            let token = rest.prefix { $0.isLetter || $0 == "_" }
            if let type = ClaimType(rawValue: String(token).lowercased()) {
                out[n - 1] = type
            }
        }
        return out
    }

    // MARK: - Adjudication types

    /// The judgment on a candidate-conflict claim pair.
    public enum Verdict: String, Codable, Equatable, CaseIterable {
        /// A genuine continuity error — the two claims cannot both hold.
        case contradiction
        /// No conflict (includes a character lying, a paraphrase, or
        /// claims that simply do not bear on each other).
        case consistent
        /// A legitimate change over story time — growth, a haircut, a
        /// promotion. Not an error.
        case evolution
    }

    public struct Adjudication: Codable, Equatable {
        public var verdict: Verdict
        /// 0…1 — the model's confidence in the verdict.
        public var confidence: Double
        public var explanation: String

        public init(verdict: Verdict, confidence: Double, explanation: String) {
            self.verdict = verdict
            self.confidence = confidence
            self.explanation = explanation
        }
    }

    // MARK: - Adjudication prompt

    /// Build the pairwise-adjudication prompt. The model sees exactly
    /// two same-subject claims — a localized judgment, far easier for a
    /// small model than whole-document reasoning (the ContraDoc
    /// lesson). Positive framing; the precision rules (dialogue =
    /// character's assertion, evolution = legitimate change) are stated
    /// as how to *classify*, not as a blacklist.
    public static func buildAdjudicationPrompt(earlier: Claim, later: Claim) -> String {
        func render(_ c: Claim, label: String) -> String {
            """
            \(label) (scene \(c.sourceSceneId), \(c.type.rawValue), spoken/written as \(c.source.rawValue)):
            \(c.value)
            Evidence: "\(c.evidenceQuote)"
            """
        }
        return """
        You are auditing a novel for continuity. Below are two claims about the same subject, the EARLIER from a scene that comes first in the story and the LATER from a scene that comes after it. Decide how they relate.

        \(render(earlier, label: "EARLIER"))

        \(render(later, label: "LATER"))

        Choose one verdict:
        - contradiction: the two claims genuinely cannot both be true of the story world. A real continuity error.
        - consistent: there is no error. The claims agree, restate the same thing, are about different things, or one of them is spoken in dialogue or held as a private thought — a character may lie or be wrong, and that is the character's assertion, not a fact about the story world.
        - evolution: the claim changed for a legitimate in-story reason over the time between the scenes — a haircut, an injury healing, a promotion, a character learning or growing.

        Judge only what the two claims say. Reply with one JSON object: verdict, confidence (0 to 1), and a one-sentence explanation.
        """
    }

    /// Build the knowledge-violation adjudication prompt.
    ///
    /// The deterministic knowledge check (`ContinuityKnowledgeCheck`)
    /// already established the ordering — the LATER claim is the
    /// *earliest* scene found that might reveal what the EARLIER claim
    /// refers to. The adjudicator's one job is to **validate the
    /// match**: do the two claims genuinely concern the same revealed
    /// fact? It deliberately does NOT re-litigate "could the character
    /// already know it" — that needs whole-story knowledge the pair
    /// does not carry, and an earlier reveal, if one exists, is the
    /// extraction's job to surface (it would then be the candidate
    /// reveal instead). Narrowing the question this way fixed both the
    /// §17 false positive *and* the over-conservative rejection of the
    /// genuine violation.
    public static func buildKnowledgeAdjudicationPrompt(reference: Claim, reveal: Claim) -> String {
        return """
        You are auditing a novel for continuity. A character refers to or knows a fact in an EARLIER scene. A LATER scene has been identified as the place that fact appears to be revealed. The ordering is already established — your one job is to decide whether the LATER claim genuinely reveals the SAME fact the EARLIER claim refers to.

        EARLIER — what the character knows or refers to (scene \(reference.sourceSceneId), \(reference.source.rawValue)):
        \(reference.value)
        Evidence: "\(reference.evidenceQuote)"

        LATER — the candidate reveal (scene \(reveal.sourceSceneId), \(reveal.source.rawValue)):
        \(reveal.value)
        Evidence: "\(reveal.evidenceQuote)"

        Choose one verdict:
        - contradiction: the LATER claim establishes the very fact the EARLIER claim refers to — so the character refers to it before the story reveals it. A genuine continuity error.
        - consistent: not an error — the LATER claim does not establish what the EARLIER one refers to; the two claims are about different things, or the LATER claim is unrelated.

        Judge only whether the two claims concern the same revealed fact. Reply with one JSON object: verdict, confidence (0 to 1), and a one-sentence explanation.
        """
    }

    public static func adjudicationJSONSchema() -> [String: Any] {
        return [
            "type": "object",
            "properties": [
                "verdict": ["type": "string", "enum": Verdict.allCases.map(\.rawValue)],
                "confidence": ["type": "number"],
                "explanation": ["type": "string"],
            ],
            "required": ["verdict", "confidence", "explanation"],
        ]
    }

    // MARK: - Adjudication parser

    private struct RawAdjudication: Decodable {
        let verdict: String?
        let confidence: Double?
        let explanation: String?
    }

    /// Parse the model's adjudication object. Tolerates preamble /
    /// postamble; clamps `confidence` into 0…1; throws on an unknown
    /// verdict or a missing object.
    public static func parseAdjudication(_ raw: String) throws -> Adjudication {
        guard let first = raw.firstIndex(of: "{") else {
            throw ParseError.noJSONObjectFound
        }
        let blocks = topLevelObjects(in: raw, from: first)
        guard let objText = blocks.first,
              let data = objText.data(using: .utf8),
              let item = try? JSONDecoder().decode(RawAdjudication.self, from: data)
        else {
            throw ParseError.malformedJSON
        }
        guard let v = item.verdict, let verdict = Verdict(rawValue: v) else {
            throw ParseError.malformedJSON
        }
        let confidence = min(1.0, max(0.0, item.confidence ?? 0.0))
        return Adjudication(
            verdict: verdict,
            confidence: confidence,
            explanation: item.explanation ?? ""
        )
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
