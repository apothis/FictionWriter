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
}
