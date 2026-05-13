import Foundation

/// Phase 7.a.1 — Pass-A beat extraction (pure-data layer).
///
/// Surface mirrors [`LedgerExtraction`](../Generation/LedgerExtraction.swift):
/// three load-bearing pure-data functions consumed by the spike runner
/// (`Tools/SceneTemplateSpike`) and (eventually) by a production
/// `BeatExtractionPipeline` in Phase 7.b:
///
/// 1. `buildExtractionPrompt(sourceProse:)` — the instruction text
///    the Ollama gemma4_2b extractor sees.
/// 2. `jsonSchema()` — the response-shape constraint, passed to
///    Ollama's `format` parameter.
/// 3. `parseExtractedSkeleton(_:)` — tolerant parser for the model's
///    JSON output (handles preamble/postamble, mirrors
///    `LedgerExtraction.parseExtractedFacts`).
///
/// Architecturally pinned in
/// [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md) §7.1.
public enum BeatExtraction {

    // MARK: - Prompt

    public static let instruction =
        "Analyze the narrative scene below. Extract its STRUCTURAL SKELETON for use as a generation template."

    public static func buildExtractionPrompt(sourceProse: String) -> String {
        return """
        \(instruction)

        Identify 5–12 discrete narrative beats — functional units of
        roughly 50–150 words that advance the scene. For each beat,
        output:

        - index: 0-based ordinal in the scene
        - function: one of [setup, arrival, escalation, reveal, conflict,
          reaction, resolution, exit]
        - modality: one of [action, dialogue, interiority, description,
          summary, mixed]
        - summary: one sentence. Replace character names with role tokens
          like {PROTAGONIST}, {ANTAGONIST}, {ALLY_1}, {WITNESS_1}. Replace
          specific place names with abstractions like {INDOOR_PRIVATE_SPACE}
          or {OUTDOOR_PUBLIC_SPACE}. This is critical — the summaries are
          re-used as a template skeleton for new scenes with different
          casts; literal names must not leak through.
        - targetWords: approximate word count for this beat
        - wordRangeStart, wordRangeEnd: word offsets in the source (0-indexed)
        - beatTensionChange: integer in [-3, +3] representing this beat's
          CHANGE in narrative tension (not a cumulative level). Negative
          values are allowed when the beat eases tension. 0 means
          tension does not move.

        Also extract:

        - sourceCharacters: distinct character names appearing in the
          scene (so the new-scene caller can map them to a target cast)
        - sourceSettingMarkers: place / time / object tokens that anchor
          the setting and would need substitution

        Scene:
        \(sourceProse)

        Output JSON:
        """
    }

    // MARK: - JSON Schema (Ollama `format` parameter)

    /// Schema constrains Ollama's structured-outputs decoder. Same
    /// shape as `ExtractedSceneSkeleton`'s Codable layout. The enum
    /// constraints on `function` and `modality` are the load-bearing
    /// reliability win — without them the model emits free-form
    /// strings ("set-up", "reveal/conflict") that the parser rejects.
    public static func jsonSchema() -> [String: Any] {
        let beatSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "index": ["type": "integer"],
                "function": [
                    "type": "string",
                    "enum": BeatFunction.allCases.map(\.rawValue),
                ],
                "modality": [
                    "type": "string",
                    "enum": NarrativeMode.allCases.map(\.rawValue),
                ],
                "summary": ["type": "string"],
                "targetWords": ["type": "integer"],
                "wordRangeStart": ["type": "integer"],
                "wordRangeEnd": ["type": "integer"],
                "beatTensionChange": ["type": "integer"],
            ],
            "required": [
                "index", "function", "modality", "summary",
                "targetWords", "wordRangeStart", "wordRangeEnd",
                "beatTensionChange",
            ],
        ]

        // Phase 7.b prompt-revision punchlist item 4: pacingStats
        // dropped post-§7.a.1. The LLM under-counted sentences by
        // 40-60% in spike runs; computed ground-truth via
        // `PacingStats.compute(text:)` is exact + free.
        return [
            "type": "object",
            "properties": [
                "beats": [
                    "type": "array",
                    "items": beatSchema,
                ],
                "sourceCharacters": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
                "sourceSettingMarkers": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
            "required": [
                "beats", "sourceCharacters", "sourceSettingMarkers",
            ],
        ]
    }

    // MARK: - Response parser

    public enum ParseError: Error, Equatable {
        case noJSONObjectFound
        case decodingFailed(String)
    }

    /// Parse the extractor's response. Tolerates preamble + postamble
    /// the model often wraps structured output in (matches the
    /// `LedgerExtraction.parseExtractedFacts` strategy). Strategy:
    /// locate the outermost balanced `{...}`, decode as
    /// `ExtractedSceneSkeleton`.
    public static func parseExtractedSkeleton(_ raw: String) throws -> ExtractedSceneSkeleton {
        guard let firstBrace = raw.firstIndex(of: "{") else {
            throw ParseError.noJSONObjectFound
        }

        // Locate the matching closing brace by depth-counting; quotes
        // mask braces. This handles the common preamble/postamble
        // case without over-engineering for adversarial input.
        var depth = 0
        var inString = false
        var escape = false
        var closeIdx: String.Index? = nil
        var i = firstBrace
        while i < raw.endIndex {
            let ch = raw[i]
            if escape {
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        closeIdx = i
                        break
                    }
                }
            }
            i = raw.index(after: i)
        }

        guard let close = closeIdx else {
            throw ParseError.noJSONObjectFound
        }
        let jsonSubstring = raw[firstBrace...close]
        guard let data = String(jsonSubstring).data(using: .utf8) else {
            throw ParseError.decodingFailed("utf8 conversion failed")
        }

        do {
            return try JSONDecoder().decode(ExtractedSceneSkeleton.self, from: data)
        } catch {
            throw ParseError.decodingFailed(String(describing: error))
        }
    }
}
