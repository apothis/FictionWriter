import Foundation

/// Phase 7 Scene-Template Generation — data structs for the Pass-A
/// extraction output. Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md)
/// §6.
///
/// A `SceneBeat` is one functional unit (50–150 words target) inside a
/// template scene. The Pass-A extractor produces a list of these; Pass-B
/// generation iterates the list one beat at a time. The
/// `summary` field is **content-stripped** per D4 (STRAP-style):
/// character names replaced with role tokens (`{PROTAGONIST}`,
/// `{ANTAGONIST}`), so the model never sees the source's literal cast
/// at generation time.
public struct SceneBeat: Codable, Equatable {
    public let index: Int
    public let summary: String
    public let modality: NarrativeMode
    public let function: BeatFunction
    public let targetWords: Int
    public let wordRangeStart: Int
    public let wordRangeEnd: Int
    /// Per-beat *change* in narrative tension, integer in [-3, +3].
    /// Renamed from `tensionDelta` post-§7.a.1 — the legacy name read
    /// as cumulative-level on one run of fixture 01 (the model emitted
    /// monotonically-increasing 0..11 values), and the rename forces
    /// semantic clarity in the prompt. Decoder accepts both keys for
    /// forward-load of legacy `.beats.json` sidecars.
    public let beatTensionChange: Int

    public init(
        index: Int,
        summary: String,
        modality: NarrativeMode,
        function: BeatFunction,
        targetWords: Int,
        wordRangeStart: Int,
        wordRangeEnd: Int,
        beatTensionChange: Int
    ) {
        self.index = index
        self.summary = summary
        self.modality = modality
        self.function = function
        self.targetWords = targetWords
        self.wordRangeStart = wordRangeStart
        self.wordRangeEnd = wordRangeEnd
        self.beatTensionChange = beatTensionChange
    }

    private enum CodingKeys: String, CodingKey {
        case index, summary, modality, function, targetWords
        case wordRangeStart, wordRangeEnd, beatTensionChange
        case tensionDelta  // legacy alias accepted on decode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try c.decode(Int.self, forKey: .index)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.modality = try c.decode(NarrativeMode.self, forKey: .modality)
        self.function = try c.decode(BeatFunction.self, forKey: .function)
        self.targetWords = try c.decode(Int.self, forKey: .targetWords)
        self.wordRangeStart = try c.decode(Int.self, forKey: .wordRangeStart)
        self.wordRangeEnd = try c.decode(Int.self, forKey: .wordRangeEnd)
        // Prefer beatTensionChange (current name); fall back to
        // tensionDelta (legacy). Default to 0 if neither present.
        if let v = try c.decodeIfPresent(Int.self, forKey: .beatTensionChange) {
            self.beatTensionChange = v
        } else if let v = try c.decodeIfPresent(Int.self, forKey: .tensionDelta) {
            self.beatTensionChange = v
        } else {
            self.beatTensionChange = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(index, forKey: .index)
        try c.encode(summary, forKey: .summary)
        try c.encode(modality, forKey: .modality)
        try c.encode(function, forKey: .function)
        try c.encode(targetWords, forKey: .targetWords)
        try c.encode(wordRangeStart, forKey: .wordRangeStart)
        try c.encode(wordRangeEnd, forKey: .wordRangeEnd)
        try c.encode(beatTensionChange, forKey: .beatTensionChange)
    }
}

/// Beat-function taxonomy drawn from common screenwriting craft. The
/// 8 cases cover the functional vocabulary the extractor maps prose
/// onto. Verified empirically in Phase 7.a.1; refined / extended if
/// the taxonomy doesn't fit observed scenes well.
public enum BeatFunction: String, Codable, Equatable, CaseIterable {
    case setup
    case arrival
    case escalation
    case reveal
    case conflict
    case reaction
    case resolution
    case exit
}

/// Pass-A output bundle: the beat list plus the structural metadata
/// (character / setting markers for the substitution pipeline, pacing
/// stats for the per-beat pacing-target prompt).
public struct ExtractedSceneSkeleton: Codable, Equatable {
    public var beats: [SceneBeat]
    public var sourceCharacters: [String]
    public var sourceSettingMarkers: [String]

    public init(
        beats: [SceneBeat],
        sourceCharacters: [String],
        sourceSettingMarkers: [String]
    ) {
        self.beats = beats
        self.sourceCharacters = sourceCharacters
        self.sourceSettingMarkers = sourceSettingMarkers
    }

    private enum CodingKeys: String, CodingKey {
        case beats, sourceCharacters, sourceSettingMarkers
        case pacingStats  // legacy; ignored on decode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.beats = try c.decode([SceneBeat].self, forKey: .beats)
        self.sourceCharacters = try c.decode([String].self, forKey: .sourceCharacters)
        self.sourceSettingMarkers = try c.decode([String].self, forKey: .sourceSettingMarkers)
        // Legacy pacingStats key is silently ignored if present —
        // post-§7.a.1 we compute pacing from source via
        // `PacingStats.compute(text:)` rather than trusting the
        // LLM's self-reported numbers.
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(beats, forKey: .beats)
        try c.encode(sourceCharacters, forKey: .sourceCharacters)
        try c.encode(sourceSettingMarkers, forKey: .sourceSettingMarkers)
    }
}

/// Numeric pacing fingerprint. Used both as Pass-A output (per-template)
/// and as the runtime comparator for Pass-B's post-hoc verification
/// (per D6). Computed via `PacingStats.compute(text:)` for ground-truth;
/// can also be reported by the extractor LLM, in which case the spike
/// runner compares the two.
public struct PacingStats: Codable, Equatable {
    public var sentenceCount: Int
    public var meanSentenceLengthWords: Double
    public var sentenceLengthStdDev: Double
    public var shortSentenceRatio: Double
    public var longSentenceRatio: Double
    public var paragraphLengthMean: Double
    public var paragraphLengthStdDev: Double
    public var dialogueRatio: Double

    public init(
        sentenceCount: Int,
        meanSentenceLengthWords: Double,
        sentenceLengthStdDev: Double,
        shortSentenceRatio: Double,
        longSentenceRatio: Double,
        paragraphLengthMean: Double,
        paragraphLengthStdDev: Double,
        dialogueRatio: Double
    ) {
        self.sentenceCount = sentenceCount
        self.meanSentenceLengthWords = meanSentenceLengthWords
        self.sentenceLengthStdDev = sentenceLengthStdDev
        self.shortSentenceRatio = shortSentenceRatio
        self.longSentenceRatio = longSentenceRatio
        self.paragraphLengthMean = paragraphLengthMean
        self.paragraphLengthStdDev = paragraphLengthStdDev
        self.dialogueRatio = dialogueRatio
    }

    public static let zero = PacingStats(
        sentenceCount: 0,
        meanSentenceLengthWords: 0,
        sentenceLengthStdDev: 0,
        shortSentenceRatio: 0,
        longSentenceRatio: 0,
        paragraphLengthMean: 0,
        paragraphLengthStdDev: 0,
        dialogueRatio: 0
    )

    /// Ground-truth pacing computation. The extractor LLM is asked to
    /// report its own pacing read in the JSON output; this helper
    /// computes the actual numbers from the source for comparison +
    /// for Pass-B's per-beat pacing target.
    ///
    /// Sentence splitting is dialogue-aware-ish: `.`, `!`, `?` boundaries,
    /// with a tolerance for `"He said, "Hello.""` patterns. Not perfect;
    /// for the spike, "close enough" is the bar — the hand-grading rubric
    /// in `LOOM_SCENE_TEMPLATE_SPIKE.md` notes when computed pacing
    /// diverges meaningfully from a human reader's intuition.
    ///
    /// Dialogue ratio is the fraction of words inside straight double
    /// quotes — crude but stable across fixtures.
    public static func compute(text: String) -> PacingStats {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .zero }

        let sentences = splitSentences(trimmed)
        guard !sentences.isEmpty else { return .zero }

        let wordCounts = sentences.map { sentenceWords($0).count }
        let mean = Double(wordCounts.reduce(0, +)) / Double(sentences.count)
        let variance = wordCounts.reduce(0.0) { acc, n in
            acc + pow(Double(n) - mean, 2)
        } / Double(sentences.count)
        let std = sqrt(variance)

        let short = wordCounts.filter { $0 < 8 }.count
        let long = wordCounts.filter { $0 > 20 }.count

        // Paragraph splits on blank lines.
        let paragraphs = trimmed.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let paragraphWordCounts = paragraphs.map { sentenceWords($0).count }
        let pMean = paragraphWordCounts.isEmpty ? 0 : Double(paragraphWordCounts.reduce(0, +)) / Double(paragraphWordCounts.count)
        let pVar = paragraphWordCounts.isEmpty ? 0 : paragraphWordCounts.reduce(0.0) { acc, n in
            acc + pow(Double(n) - pMean, 2)
        } / Double(paragraphWordCounts.count)
        let pStd = sqrt(pVar)

        let dialogueWords = countDialogueWords(in: trimmed)
        let totalWords = sentenceWords(trimmed).count
        let dialogueRatio = totalWords == 0 ? 0 : Double(dialogueWords) / Double(totalWords)

        return PacingStats(
            sentenceCount: sentences.count,
            meanSentenceLengthWords: mean,
            sentenceLengthStdDev: std,
            shortSentenceRatio: Double(short) / Double(sentences.count),
            longSentenceRatio: Double(long) / Double(sentences.count),
            paragraphLengthMean: pMean,
            paragraphLengthStdDev: pStd,
            dialogueRatio: dialogueRatio
        )
    }

    private static func splitSentences(_ text: String) -> [String] {
        // Walk character-by-character collecting sentences. Quote-aware:
        // a `.` inside `"..."` doesn't end a sentence unless the next
        // char is whitespace + capital, which we approximate as
        // "whitespace then any non-quote char." Crude but stable.
        var sentences: [String] = []
        var current = ""
        var inQuote = false
        for ch in text {
            current.append(ch)
            if ch == "\"" {
                inQuote.toggle()
                continue
            }
            if !inQuote, ch == "." || ch == "!" || ch == "?" {
                let stripped = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    sentences.append(stripped)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private static func sentenceWords(_ sentence: String) -> [Substring] {
        sentence.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    }

    private static func countDialogueWords(in text: String) -> Int {
        var count = 0
        var inQuote = false
        var buffer = ""
        for ch in text {
            if ch == "\"" {
                if inQuote {
                    // End of quoted segment — count the words in `buffer`.
                    count += sentenceWords(buffer).count
                    buffer = ""
                }
                inQuote.toggle()
                continue
            }
            if inQuote { buffer.append(ch) }
        }
        return count
    }
}
