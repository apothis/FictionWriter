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

    /// **Flat** Pass-A schema + prompt + parser — the production shape.
    ///
    /// Every other shape failed on the available models (2026-05-22):
    /// the nested single object flaked under Ollama `format` and
    /// degenerated under GBNF on a Thinking writer; unconstrained,
    /// gemma4_2b free-formed a wrong schema (nested) or reverted to prose
    /// / wrong-key JSON (JSONL). The fix: a **flat structure-of-arrays**
    /// object — no nested objects, no arrays-of-objects — which (a) the
    /// Ollama `format` decoder constrains reliably (the flake was the
    /// deep nesting) and (b) a small model can actually produce.
    ///
    /// Shape: one object with the voice fields at top level + parallel
    /// arrays `beatFunctions` / `beatModalities` / `beatSummaries` /
    /// `beatTargetWords` (zipped by index into beats).
    public static func flatJSONSchema() -> [String: Any] {
        return [
            "type": "object",
            "properties": [
                "sentenceCadence": ["type": "string", "enum": SentenceCadence.allCases.map(\.rawValue)],
                "dialogueDensity": ["type": "string", "enum": DialogueDensity.allCases.map(\.rawValue)],
                "rhetoricalFlourish": ["type": "string", "enum": RhetoricalFlourish.allCases.map(\.rawValue)],
                "register": ["type": "string"],
                "distinctiveTechniques": ["type": "array", "items": ["type": "string"]],
                "characters": ["type": "array", "items": ["type": "string"]],
                "settings": ["type": "array", "items": ["type": "string"]],
                "beatFunctions": ["type": "array", "items": ["type": "string", "enum": BeatFunction.allCases.map(\.rawValue)]],
                "beatModalities": ["type": "array", "items": ["type": "string", "enum": NarrativeMode.allCases.map(\.rawValue)]],
                "beatSummaries": ["type": "array", "items": ["type": "string"]],
                "beatTargetWords": ["type": "array", "items": ["type": "integer"]],
            ],
            "required": [
                "sentenceCadence", "dialogueDensity", "rhetoricalFlourish",
                "register", "distinctiveTechniques", "characters", "settings",
                "beatFunctions", "beatModalities", "beatSummaries", "beatTargetWords",
            ],
        ]
    }

    /// Flat-shape prompt. Scene first, directive last (recency); a
    /// worked example pins the exact flat shape. Used with `format:
    /// flatJSONSchema()` on Ollama (the schema forces the keys) and
    /// unconstrained on a Kobold fallback.
    public static func buildFlatPrompt(sourceProse: String) -> String {
        return """
        You convert a narrative scene into a structural skeleton. Read the SCENE, then output ONE JSON object describing it.

        SCENE:
        \(sourceProse)

        ===
        Now output ONLY a single JSON object — no prose, no markdown, no analysis. First character must be `{`. Use exactly these keys, with the parallel beat arrays the same length (5–12 entries), in order:

        {"sentenceCadence":"shortClipped|moderateBalanced|longFlowing","dialogueDensity":"dialogueHeavy|balanced|narrativeHeavy","rhetoricalFlourish":"minimal|moderate|ornate","register":"short phrase e.g. noir minimalism","distinctiveTechniques":["2-5 specific craft moves"],"characters":["names in the scene"],"settings":["place/time/object markers"],"beatFunctions":["setup","escalation","reveal"],"beatModalities":["description","action","dialogue"],"beatSummaries":["one sentence per beat using role tokens {PROTAGONIST}/{ANTAGONIST}, never literal names","..."],"beatTargetWords":[80,120,60]}

        Rules: beatFunctions ∈ setup|arrival|escalation|reveal|conflict|reaction|resolution|exit; beatModalities ∈ action|dialogue|interiority|description|summary|mixed; the four beat arrays are equal length; beatSummaries use role tokens, never literal names; beatTargetWords are real 50–150 estimates.

        Begin now (JSON only):
        """
    }

    /// Tolerant flat-shape parser. Finds the outermost `{...}`, zips the
    /// parallel beat arrays into `SceneBeat`s (by `beatSummaries` count;
    /// missing function/modality/targetWords default sensibly,
    /// `targetWords ≤ 0 → 100`), reads the voice fields + character/
    /// setting markers from the top level. Throws `noJSONObjectFound`
    /// when there are no beat summaries (so the extractor retries).
    public static func parseFlatSkeleton(_ raw: String) throws -> ExtractedSceneSkeleton {
        guard let open = raw.firstIndex(of: "{"),
              let close = raw.lastIndex(of: "}"), open < close else {
            throw ParseError.noJSONObjectFound
        }
        let jsonStr = String(raw[open...close])
        guard let data = jsonStr.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw ParseError.decodingFailed("flat object was not valid JSON") }

        let summaries = stringArray(obj["beatSummaries"]) ?? []
        guard !summaries.isEmpty else { throw ParseError.noJSONObjectFound }
        let funcs = stringArray(obj["beatFunctions"]) ?? []
        let mods = stringArray(obj["beatModalities"]) ?? []
        let targets = (obj["beatTargetWords"] as? [Any])?.compactMap { intValue($0) } ?? []

        var beats: [SceneBeat] = []
        for (i, summary) in summaries.enumerated() {
            guard !summary.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let fn = i < funcs.count ? (BeatFunction(rawValue: funcs[i]) ?? .escalation) : .escalation
            let md = i < mods.count ? (NarrativeMode(rawValue: mods[i]) ?? .mixed) : .mixed
            let tw = (i < targets.count && targets[i] > 0) ? targets[i] : 100
            beats.append(SceneBeat(
                index: i, summary: summary, modality: md, function: fn,
                targetWords: tw, wordRangeStart: 0, wordRangeEnd: 0, beatTensionChange: 0
            ))
        }
        guard !beats.isEmpty else { throw ParseError.noJSONObjectFound }
        return ExtractedSceneSkeleton(
            beats: beats,
            sourceCharacters: stringArray(obj["characters"]) ?? [],
            sourceSettingMarkers: stringArray(obj["settings"]) ?? [],
            voiceDescriptor: voiceFromDict(obj)
        )
    }

    // MARK: - Skeleton normalization

    /// Adjacent-summary Jaccard threshold above which two beats are
    /// treated as the same beat and merged. 0.8 = "near-identical"
    /// (a one-word difference in a five-word summary). Tuned to catch
    /// the extractor re-emitting essentially the same beat twice
    /// without collapsing genuinely distinct-but-related beats.
    private static let beatMergeThreshold = 0.8

    /// Post-process a freshly-extracted skeleton to curb two
    /// skeleton-quality problems seen on monologue-heavy exemplars
    /// (2026-05-22 test5 run): out-of-order beat `index` values and
    /// near-duplicate adjacent beats that Pass-B then re-renders.
    ///
    /// Steps: (1) sort beats by their reported `index` (chronological
    /// safety net); (2) merge adjacent beats whose summaries are
    /// near-identical (`beatMergeThreshold`), summing their target
    /// word budgets and extending the word range; (3) re-index the
    /// survivors 0..n-1. Voice descriptor + character/setting markers
    /// pass through untouched.
    public static func normalizeSkeleton(_ skeleton: ExtractedSceneSkeleton) -> ExtractedSceneSkeleton {
        let sorted = skeleton.beats.sorted { $0.index < $1.index }

        var merged: [SceneBeat] = []
        for beat in sorted {
            if let last = merged.last,
               summarySimilarity(last.summary, beat.summary) >= beatMergeThreshold {
                merged[merged.count - 1] = SceneBeat(
                    index: last.index, summary: last.summary,
                    modality: last.modality, function: last.function,
                    targetWords: last.targetWords + beat.targetWords,
                    wordRangeStart: last.wordRangeStart,
                    wordRangeEnd: max(last.wordRangeEnd, beat.wordRangeEnd),
                    beatTensionChange: last.beatTensionChange
                )
            } else {
                merged.append(beat)
            }
        }

        let reindexed = merged.enumerated().map { (i, b) in
            SceneBeat(
                index: i, summary: b.summary, modality: b.modality,
                function: b.function, targetWords: b.targetWords,
                wordRangeStart: b.wordRangeStart, wordRangeEnd: b.wordRangeEnd,
                beatTensionChange: b.beatTensionChange
            )
        }

        return ExtractedSceneSkeleton(
            beats: reindexed,
            sourceCharacters: skeleton.sourceCharacters,
            sourceSettingMarkers: skeleton.sourceSettingMarkers,
            voiceDescriptor: skeleton.voiceDescriptor
        )
    }

    /// Word-set Jaccard similarity of two beat summaries, case- and
    /// punctuation-insensitive. 0 when both are empty of word tokens.
    private static func summarySimilarity(_ a: String, _ b: String) -> Double {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init))
        }
        let ta = tokens(a)
        let tb = tokens(b)
        let union = ta.union(tb)
        guard !union.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(union.count)
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
