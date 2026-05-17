import Foundation

/// Planned Project mode — Phase 2: the premise → outline pipeline.
///
/// Staged expansion (LOOM_PLANNED_PROJECT.md §4): Stage 0 sizing is
/// `OutlineSizing` (deterministic); Stage 1 fills the framework's beat
/// slots from the premise; Stage 2 maps beats to chapters; Stage 3
/// expands chapters into scenes. This namespace holds the pure
/// prompt/parser pieces; the async orchestration lives in
/// `OutlineGenerator`.
///
/// Per the §15.19 learnings, the LLM passes run unconstrained (no
/// `format` schema — it degenerates on small models): the output
/// shape is pinned in-prompt and the parser is tolerant of preamble,
/// bullets, and markup noise.
public enum OutlineGeneration {

    /// One framework beat slot filled with story-specific content by
    /// Stage 1. `beatName` is the canonical `BeatSlot.name`.
    public struct GeneratedBeat: Equatable {
        public let beatName: String
        public let summary: String

        public init(beatName: String, summary: String) {
            self.beatName = beatName
            self.summary = summary
        }
    }

    // MARK: - Stage 1: beat generation

    /// Stage 1 prompt: premise + character sketch → one concrete
    /// sentence per framework beat. A fixed, named, ordered slot list
    /// turns open ideation into a fill-in task the small model can do
    /// reliably.
    public static func buildBeatGenerationPrompt(
        premise: String,
        characterSketch: String,
        framework: StoryFramework
    ) -> String {
        let beatList = framework.beatSlots
            .map { "- \($0.name): \($0.guidance)" }
            .joined(separator: "\n")
        let exampleBeat = framework.beatSlots.first?.name ?? "Opening Image"
        return """
        You are a story-outlining tool. Given a premise and a main character, you write one concrete beat for each named story beat below.

        Premise:
        \(premise)

        Main character:
        \(characterSketch)

        The story beats, in order — each with what it is for:
        \(beatList)

        Write exactly one line for each beat, in the order above. Each line is the beat's name, then ": ", then a single sentence describing what concretely happens at that beat in THIS story. Name the characters. Reply with only those lines, nothing else.
        For example:
        \(exampleBeat): <what concretely happens here>
        """
    }

    /// Parse a Stage 1 response: one `Beat Name: summary` line per
    /// beat. Tolerant of preamble, bullets, numbering, and bold
    /// markup; matches each line to a framework beat by name
    /// (case-insensitive). Returns the found beats in framework order.
    public static func parseGeneratedBeats(
        _ raw: String,
        framework: StoryFramework
    ) -> [GeneratedBeat] {
        var summaryByLabel: [String: String] = [:]
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = normaliseBeatLabel(String(line[..<colon]))
            let summary = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !summary.isEmpty else { continue }
            // First occurrence of a label wins.
            if summaryByLabel[label] == nil { summaryByLabel[label] = summary }
        }
        return framework.beatSlots.compactMap { slot in
            guard let summary = summaryByLabel[normaliseBeatLabel(slot.name)] else {
                return nil
            }
            return GeneratedBeat(beatName: slot.name, summary: summary)
        }
    }

    /// Normalise a beat label for matching — strip markup + whitespace,
    /// lowercase — so "**Theme Stated**" matches "Theme Stated".
    private static func normaliseBeatLabel(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Stage 2: chapter map

    /// One chapter's slice of the outline: the beats it covers (in
    /// story order) and how many scenes to generate for it.
    public struct ChapterPlan: Equatable {
        public let beats: [GeneratedBeat]
        public let sceneCount: Int

        public init(beats: [GeneratedBeat], sceneCount: Int) {
            self.beats = beats
            self.sceneCount = sceneCount
        }
    }

    /// Stage 2: map the generated beats onto chapters. Pure,
    /// deterministic — the structure is computed in code, never asked
    /// of the LLM. Beats are split into contiguous, near-even,
    /// order-preserving groups; `OutlineSizing.sceneCount` is spread
    /// the same way. A flat scenario (`chapterCount == 0`) yields a
    /// single plan covering the whole story.
    public static func planChapters(
        beats: [GeneratedBeat],
        sizing: OutlineSizing
    ) -> [ChapterPlan] {
        let chapters = max(1, sizing.chapterCount)
        let beatSizes = distribute(beats.count, into: chapters)
        let sceneSizes = distribute(sizing.sceneCount, into: chapters)
        var plans: [ChapterPlan] = []
        var cursor = 0
        for i in 0..<chapters {
            let slice = Array(beats[cursor..<(cursor + beatSizes[i])])
            cursor += beatSizes[i]
            plans.append(ChapterPlan(beats: slice, sceneCount: sceneSizes[i]))
        }
        return plans
    }

    /// Split `count` items into `groups` contiguous, near-even buckets
    /// (bucket sizes differ by at most 1, and sum to `count`).
    private static func distribute(_ count: Int, into groups: Int) -> [Int] {
        guard groups > 0 else { return [] }
        return (0..<groups).map { i in
            (count * (i + 1)) / groups - (count * i) / groups
        }
    }

    // MARK: - Stage 3: scene generation

    /// One scene as Stage 3 describes it — a title and a one-sentence
    /// summary. The orchestrator turns each into a `Scene` (status
    /// `.todo`, empty prose) when it assembles the `Manuscript`.
    public struct SceneOutline: Equatable {
        public let title: String
        public let summary: String

        public init(title: String, summary: String) {
            self.title = title
            self.summary = summary
        }
    }

    /// Stage 3 prompt: break one chapter into exactly its planned
    /// number of scenes, covering the chapter's beats in order.
    public static func buildSceneGenerationPrompt(
        chapter: ChapterPlan,
        premise: String,
        characterSketch: String
    ) -> String {
        let beatLines = chapter.beats
            .map { "- \($0.beatName): \($0.summary)" }
            .joined(separator: "\n")
        return """
        You are a story-outlining tool. Break the chapter described below into exactly \(chapter.sceneCount) scene(s).

        Premise:
        \(premise)

        Main character:
        \(characterSketch)

        This chapter covers these story beats:
        \(beatLines)

        Write exactly \(chapter.sceneCount) scene(s). Together the scenes must cover ALL of the beats listed above, in order, and the final scene must reach the chapter's last beat. If there are more beats than scenes, let earlier scenes each carry more than one beat. For each scene, write one line: a short scene title, then " | ", then a one-sentence summary of what concretely happens in that scene. Reply with only those lines, nothing else.
        For example:
        The Rooftop Run | Vesna sprints a delivery across the dawn rooftops and is ambushed.
        """
    }

    /// Parse a Stage 3 response: `title | summary` lines. Tolerant of
    /// preamble, bullets, numbering, and bold markup; a line missing
    /// the separator or either field is skipped.
    public static func parseGeneratedScenes(_ raw: String) -> [SceneOutline] {
        var out: [SceneOutline] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            guard let bar = line.firstIndex(of: "|") else { continue }
            let title = String(line[..<bar])
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            let summary = String(line[line.index(after: bar)...])
                .trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !summary.isEmpty else { continue }
            out.append(SceneOutline(title: title, summary: summary))
        }
        return out
    }

    // MARK: - Stage 4: assembly

    /// The assembled outline — a `Manuscript` structure plus the
    /// `Scene` objects it references. The caller persists both.
    /// `Codable` so the guided-creation wizard can round-trip an
    /// edited outline back to Swift over the webview bridge (Phase 4).
    public struct GeneratedOutline: Equatable, Codable {
        public let manuscript: Manuscript
        public let scenes: [Scene]

        public init(manuscript: Manuscript, scenes: [Scene]) {
            self.manuscript = manuscript
            self.scenes = scenes
        }
    }

    /// Reconcile a chapter's parsed scenes to its planned count: the
    /// deterministic count is authoritative, so a model that returned
    /// too many is truncated and too few is padded with empty
    /// placeholder scenes for the writer to fill.
    public static func reconcileScenes(
        _ parsed: [SceneOutline], target: Int
    ) -> [SceneOutline] {
        guard target > 0 else { return [] }
        if parsed.count == target { return parsed }
        if parsed.count > target { return Array(parsed.prefix(target)) }
        var out = parsed
        for n in (parsed.count + 1)...target {
            out.append(SceneOutline(title: "Scene \(n)", summary: ""))
        }
        return out
    }

    /// Stage 4: turn the per-chapter scene outlines into a populated
    /// `Manuscript` + its `Scene` objects (status `.todo`, empty
    /// prose). A flat scenario (`chapterCount == 0`) puts every scene
    /// in `orphanedSceneIds`; a chaptered one builds a single `Part`.
    public static func assembleOutline(
        plans: [ChapterPlan],
        scenesPerChapter: [[SceneOutline]],
        sizing: OutlineSizing
    ) -> GeneratedOutline {
        var allScenes: [Scene] = []
        var chapters: [Chapter] = []
        for (index, pair) in zip(plans, scenesPerChapter).enumerated() {
            let (plan, parsedScenes) = pair
            let reconciled = reconcileScenes(parsedScenes, target: plan.sceneCount)
            let sceneObjs = reconciled.map { o in
                Scene(
                    id: UUID(), title: o.title, status: .todo,
                    summary: o.summary, targetWordCount: sizing.perSceneWords
                )
            }
            allScenes.append(contentsOf: sceneObjs)
            chapters.append(Chapter(
                title: "Chapter \(index + 1)",
                sceneIds: sceneObjs.map(\.id),
                targetWordCount: plan.sceneCount * sizing.perSceneWords
            ))
        }
        let manuscript: Manuscript
        if sizing.chapterCount == 0 {
            manuscript = Manuscript(orphanedSceneIds: allScenes.map(\.id))
        } else {
            manuscript = Manuscript(parts: [Part(title: "Manuscript", chapters: chapters)])
        }
        return GeneratedOutline(manuscript: manuscript, scenes: allScenes)
    }
}
