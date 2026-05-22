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
        - voiceDescriptor: a five-field fingerprint of the prose voice,
          used as a positive constraint when the writer generates a new
          scene in this style:
          - sentenceCadence: shortClipped (Hemingway / Carver, bare
            declaratives, no subordination) | moderateBalanced (mix of
            short and long) | longFlowing (Conrad / Faulkner / McCarthy
            periodic sentences with nested subordinate clauses)
          - dialogueDensity: dialogueHeavy | balanced | narrativeHeavy
          - rhetoricalFlourish: minimal (no metaphor, no adornment) |
            moderate | ornate (lyrical / image-dense)
          - register: a short phrase characterising the voice
            (e.g., "noir minimalism", "Hemingway-clipped", "Conrad-
            adjacent periodic prose", "Cormac McCarthy biblical",
            "Victorian three-decker")
          - distinctiveTechniques: 2–5 bullet points naming SPECIFIC
            craft moves the prose uses. Be surgically specific — these
            bullets are the most useful signal the writer will see.
            Each bullet must name a technique actually present in
            THIS scene; do not output generic descriptions that could
            apply to any prose.

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
        let voiceDescriptorSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "sentenceCadence": [
                    "type": "string",
                    "enum": SentenceCadence.allCases.map(\.rawValue),
                ],
                "dialogueDensity": [
                    "type": "string",
                    "enum": DialogueDensity.allCases.map(\.rawValue),
                ],
                "rhetoricalFlourish": [
                    "type": "string",
                    "enum": RhetoricalFlourish.allCases.map(\.rawValue),
                ],
                "register": ["type": "string"],
                "distinctiveTechniques": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
            "required": [
                "sentenceCadence", "dialogueDensity",
                "rhetoricalFlourish", "register",
                "distinctiveTechniques",
            ],
        ]
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
                "voiceDescriptor": voiceDescriptorSchema,
            ],
            "required": [
                "beats", "sourceCharacters", "sourceSettingMarkers",
                "voiceDescriptor",
            ],
        ]
    }

    // MARK: - GBNF grammar (KoboldCpp `grammar` parameter)

    /// GBNF grammar for the `ExtractedSceneSkeleton` shape. Used by the
    /// Kobold-writer beat-extraction path (`KoboldBeatExtractor`) as the
    /// reliable structural constraint — the Ollama `format`-schema path
    /// flakes (LOOM_TECH_STACK §3: ~50% degenerate on small gemma; and
    /// live 2026-05-22 it produced a 97KB off-schema body on the writer
    /// model). GBNF guarantees well-formed, on-shape JSON at the sampler
    /// level instead.
    ///
    /// Mirrors `jsonSchema()`: same keys, same enum constraints on
    /// `function` / `modality` / the three voice-descriptor enum fields.
    /// All four top-level keys are required (the voice descriptor is the
    /// load-bearing generation signal — we want the model forced to emit
    /// it, not allowed to skip it).
    ///
    /// Empirical guards inherited from `LedgerExtraction.gbnfGrammar`:
    /// each rule definition is one line (multi-line defs failed grammar
    /// compilation on KoboldCpp v1.111), and `ws ::= " "?` rather than a
    /// greedy whitespace class (the greedy form let the model stall
    /// emitting unbounded whitespace between fields).
    public static func gbnfGrammar() -> String {
        func enumAlt<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String
        where T.RawValue == String {
            T.allCases.map { "\"\\\"\($0.rawValue)\\\"\"" }.joined(separator: " | ")
        }
        // A `"key":` literal as a grammar token.
        func key(_ k: String) -> String { "\"\\\"\(k)\\\":\"" }

        let funcAlt = enumAlt(BeatFunction.self)
        let modAlt = enumAlt(NarrativeMode.self)
        let cadAlt = enumAlt(SentenceCadence.self)
        let densAlt = enumAlt(DialogueDensity.self)
        let flourAlt = enumAlt(RhetoricalFlourish.self)

        let beat = "beat ::= \"{\" ws "
            + key("index") + " ws integer ws \",\" ws "
            + key("function") + " ws (\(funcAlt)) ws \",\" ws "
            + key("modality") + " ws (\(modAlt)) ws \",\" ws "
            + key("summary") + " ws string ws \",\" ws "
            + key("targetWords") + " ws integer ws \",\" ws "
            + key("wordRangeStart") + " ws integer ws \",\" ws "
            + key("wordRangeEnd") + " ws integer ws \",\" ws "
            + key("beatTensionChange") + " ws integer ws \"}\""

        let voice = "voice ::= \"{\" ws "
            + key("sentenceCadence") + " ws (\(cadAlt)) ws \",\" ws "
            + key("dialogueDensity") + " ws (\(densAlt)) ws \",\" ws "
            + key("rhetoricalFlourish") + " ws (\(flourAlt)) ws \",\" ws "
            + key("register") + " ws string ws \",\" ws "
            + key("distinctiveTechniques") + " ws strarray ws \"}\""

        let root = "root ::= \"{\" ws "
            + key("beats") + " ws beats ws \",\" ws "
            + key("sourceCharacters") + " ws strarray ws \",\" ws "
            + key("sourceSettingMarkers") + " ws strarray ws \",\" ws "
            + key("voiceDescriptor") + " ws voice ws \"}\""

        return root + "\n"
            + "beats ::= \"[\" ws (beat (ws \",\" ws beat)*)? ws \"]\"\n"
            + beat + "\n"
            + voice + "\n"
            + "strarray ::= \"[\" ws (string (ws \",\" ws string)*)? ws \"]\"\n"
            + "integer ::= \"-\"? [0-9]+\n"
            + "string ::= \"\\\"\" ([^\"\\\\] | \"\\\\\" .)* \"\\\"\"\n"
            + "ws ::= \" \"?"
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

    // MARK: - JSONL prompt + parser (the production path)

    /// JSONL Pass-A prompt — the shape small/instruct models reliably
    /// produce (the ledger/continuity extractors use the same family).
    /// The previous single-nested-object schema (`buildExtractionPrompt`
    /// + `parseExtractedSkeleton`) proved too complex for gemma4_2b
    /// unconstrained (it free-formed a wrong title/characters/setting/
    /// plot shape — live 2026-05-22) and degenerated under GBNF on a
    /// Thinking writer. Flat type-discriminated lines sidestep both.
    ///
    /// Output: one JSON object per line — a `voice` line, then one
    /// `beat` line per beat, then a `meta` line. `parseJSONLSkeleton`
    /// is per-line tolerant (a bad line is skipped, not fatal).
    public static func buildJSONLPrompt(sourceProse: String) -> String {
        // Structure matters for small models: the SCENE comes first, the
        // output directive LAST, so recency keeps the model on-task. A
        // long format spec placed before a 3000-word scene gets "forgotten"
        // and gemma4_2b reverts to a prose summary (live 2026-05-22). The
        // closing "Output ONLY JSONL … begin with {" is the dominant
        // instruction; the example lines lock in the exact shape.
        return """
        You convert a narrative scene into a structural skeleton. Read the SCENE, then output the skeleton.

        SCENE:
        \(sourceProse)

        ===
        Now output ONLY the skeleton as JSONL — exactly ONE JSON object per line, nothing else. NO prose, NO markdown, NO headings, NO analysis, NO blank lines. Your first character must be `{`.

        Emit these lines, in this order:
        1) one voice line:
        {"type":"voice","sentenceCadence":"shortClipped|moderateBalanced|longFlowing","dialogueDensity":"dialogueHeavy|balanced|narrativeHeavy","rhetoricalFlourish":"minimal|moderate|ornate","register":"short phrase e.g. noir minimalism","distinctiveTechniques":["2-5 specific craft moves"]}
        2) then 5–12 beat lines in order:
        {"type":"beat","index":0,"function":"setup|arrival|escalation|reveal|conflict|reaction|resolution|exit","modality":"action|dialogue|interiority|description|summary|mixed","summary":"one sentence using role tokens {PROTAGONIST}/{ANTAGONIST}/{ALLY_1}, never literal names","targetWords":80}
        3) one meta line:
        {"type":"meta","characters":["names"],"settings":["place/time/object markers"]}

        Rules: one JSON object per line; use only the enum values shown; targetWords is a real 50–150 estimate, never 0; summary uses role tokens, never literal names.

        Begin now (JSON only):
        """
    }

    /// Tolerant JSONL parser. Walks lines; on each, extracts the
    /// `{...}` span (lenient about fences / leading prose), parses it,
    /// and routes by `type`. Unparseable / unrecognised lines are
    /// skipped. Unknown enum values fall back to a sensible default
    /// rather than dropping the beat. `targetWords` ≤ 0 → 100 (kills the
    /// degenerate-zero-budget truncation). Beats are re-indexed
    /// contiguously so Pass-B's sequential loop is clean. Throws
    /// `noJSONObjectFound` only when ZERO beats parse (so the extractor
    /// retries).
    public static func parseJSONLSkeleton(_ raw: String) throws -> ExtractedSceneSkeleton {
        var beats: [SceneBeat] = []
        var characters: [String] = []
        var settings: [String] = []
        var voice: VoiceDescriptor? = nil

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let open = line.firstIndex(of: "{"),
                  let close = line.lastIndex(of: "}"),
                  open < close else { continue }
            let jsonStr = String(line[open...close])
            guard let data = jsonStr.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            switch (obj["type"] as? String)?.lowercased() {
            case "voice":
                voice = voiceFromDict(obj)
            case "meta":
                if let c = stringArray(obj["characters"]) { characters = c }
                if let s = stringArray(obj["settings"]) { settings = s }
            case "beat":
                if let b = beatFromDict(obj, fallbackIndex: beats.count) { beats.append(b) }
            default:
                // Untyped but beat-shaped (has a summary) → treat as a beat.
                if obj["summary"] != nil, let b = beatFromDict(obj, fallbackIndex: beats.count) {
                    beats.append(b)
                }
            }
        }
        guard !beats.isEmpty else { throw ParseError.noJSONObjectFound }
        beats.sort { $0.index < $1.index }
        let reindexed = beats.enumerated().map { i, b in
            SceneBeat(
                index: i, summary: b.summary, modality: b.modality, function: b.function,
                targetWords: b.targetWords, wordRangeStart: b.wordRangeStart,
                wordRangeEnd: b.wordRangeEnd, beatTensionChange: b.beatTensionChange
            )
        }
        return ExtractedSceneSkeleton(
            beats: reindexed, sourceCharacters: characters,
            sourceSettingMarkers: settings, voiceDescriptor: voice
        )
    }

    private static func intValue(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let i = v as? Int { return i }
        if let s = v as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        return nil
    }

    private static func stringArray(_ v: Any?) -> [String]? {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return nil
    }

    private static func beatFromDict(_ obj: [String: Any], fallbackIndex: Int) -> SceneBeat? {
        guard let summary = obj["summary"] as? String,
              !summary.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let function = (obj["function"] as? String).flatMap { BeatFunction(rawValue: $0) } ?? .escalation
        let modality = (obj["modality"] as? String).flatMap { NarrativeMode(rawValue: $0) } ?? .mixed
        // Trust a sane positive targetWords; otherwise default to 100 so
        // the per-beat budget never degenerates to the truncating floor.
        let tw = intValue(obj["targetWords"]) ?? 0
        return SceneBeat(
            index: intValue(obj["index"]) ?? fallbackIndex,
            summary: summary, modality: modality, function: function,
            targetWords: tw > 0 ? tw : 100,
            wordRangeStart: 0, wordRangeEnd: 0,
            beatTensionChange: intValue(obj["beatTensionChange"]) ?? 0
        )
    }

    private static func voiceFromDict(_ obj: [String: Any]) -> VoiceDescriptor {
        VoiceDescriptor(
            sentenceCadence: (obj["sentenceCadence"] as? String).flatMap { SentenceCadence(rawValue: $0) } ?? .moderateBalanced,
            dialogueDensity: (obj["dialogueDensity"] as? String).flatMap { DialogueDensity(rawValue: $0) } ?? .balanced,
            rhetoricalFlourish: (obj["rhetoricalFlourish"] as? String).flatMap { RhetoricalFlourish(rawValue: $0) } ?? .moderate,
            register: (obj["register"] as? String) ?? "",
            distinctiveTechniques: stringArray(obj["distinctiveTechniques"]) ?? []
        )
    }
}
