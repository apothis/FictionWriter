import Foundation

/// Planned Project mode — Phase 5.1: beat planning. An outline scene
/// (`Scene.summary` + `Scene.targetWordCount`) is drafted with the
/// per-beat writer loop; before that loop can run, the summary is
/// decomposed into an ordered list of beats. The beat *count* and the
/// per-beat *word budget* are deterministic (computed here); the beat
/// *intents* — one sentence each describing what happens — come from a
/// single LLM pass over the summary.
///
/// Mirrors the staged-expansion shape of `OutlineGeneration`: a
/// prompt builder + a tolerant line parser, with the structural
/// numbers fixed in code so the model can't drift them.
public enum SceneBeatPlanning {

    /// One planned beat — a slice of the scene to be drafted in a
    /// single writer call.
    public struct PlannedBeat: Equatable {
        /// 0-based position in the scene.
        public let index: Int
        /// One sentence: what concretely happens in this beat.
        public let intent: String
        /// The beat's slice of the scene's word budget.
        public let targetWords: Int

        public init(index: Int, intent: String, targetWords: Int) {
            self.index = index
            self.intent = intent
            self.targetWords = targetWords
        }
    }

    /// Deterministic beat count for a scene of `words` target length —
    /// roughly one beat per 300 words, clamped to a sensible 2…8 so a
    /// tiny scene still gets a beginning/end and a long one doesn't
    /// fragment into dozens of micro-calls.
    public static func beatCount(forTargetWords words: Int) -> Int {
        let raw = Int((Double(max(words, 1)) / 300.0).rounded())
        return min(8, max(2, raw))
    }

    /// Prompt for the beat-planning LLM pass: break `sceneSummary`
    /// into exactly `beatCount` ordered beats, one sentence each.
    public static func buildBeatPlanPrompt(
        sceneSummary: String,
        beatCount: Int
    ) -> String {
        """
        You are a scene-planning tool. Break the scene described below into exactly \(beatCount) beats — the ordered functional units the scene moves through.

        Scene:
        \(sceneSummary)

        Write exactly \(beatCount) beat(s). For each beat, write one line: a single sentence describing what concretely happens in that beat. Keep the beats in chronological order; together they must cover the whole scene from its opening to its close. Reply with only those lines, nothing else.
        For example:
        Mara studies the vault door, listening for the patrol.
        She works the lock as the corridor lights sweep past.
        """
    }

    /// Parse the beat-planning response into exactly `beatCount`
    /// beats and distribute `targetWords` across them. Tolerant of
    /// preamble, bullets, numbering and bold markup. An over-long
    /// response is truncated; a short one is padded with placeholder
    /// beats so the per-beat loop still has the planned count to run.
    /// The word budget is split evenly, the remainder going to the
    /// earliest beats, so the per-beat targets always sum to exactly
    /// `targetWords`.
    public static func parseBeatPlan(
        _ raw: String,
        beatCount: Int,
        targetWords: Int
    ) -> [PlannedBeat] {
        guard beatCount > 0 else { return [] }

        var intents: [String] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine.drop(while: { leadingNoise.contains($0) }))
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Skip a header/preamble line ("Here is the beat plan:").
            // A beat intent is a sentence — it ends with . ! or ? —
            // never a colon, so this can't drop a real beat.
            guard !line.hasSuffix(":") else { continue }
            intents.append(line)
        }
        // Reconcile to exactly beatCount — truncate or pad.
        if intents.count > beatCount {
            intents = Array(intents.prefix(beatCount))
        } else {
            while intents.count < beatCount {
                intents.append("Continue the scene.")
            }
        }

        let base = targetWords / beatCount
        let remainder = targetWords % beatCount
        return intents.enumerated().map { (i, intent) in
            PlannedBeat(
                index: i,
                intent: intent,
                targetWords: base + (i < remainder ? 1 : 0)
            )
        }
    }

    /// Leading characters stripped from a parsed line: bullet glyphs,
    /// list numbering punctuation, and digits. Mirrors the tolerance
    /// of `OutlineGeneration`'s line parsers.
    private static let leadingNoise = "-*•0123456789.) \t"
}
