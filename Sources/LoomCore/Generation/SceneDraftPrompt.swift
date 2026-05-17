import Foundation

/// Planned Project mode — Phase 5.2: the per-beat draft prompt.
///
/// An outline scene is drafted beat by beat (one writer call per
/// planned beat). This builder assembles each call's prompt:
///
/// 1. SYSTEM framing — writer role, "write ONE beat, prose only".
/// 2. STYLE — the project's assigned genre/register styles
///    (`StylePrompt.render`), genre then register.
/// 3. SCENE — the whole scene's outline summary, so the writer knows
///    the arc the current beat sits inside.
/// 4. BEAT PLAN — every beat's intent, the current one marked. This
///    doubles as the running summary: it already says what every
///    earlier beat covered.
/// 5. SEAM — only a short trailing slice of the prose so far, for
///    voice continuity. The whole accumulated draft is deliberately
///    NOT embedded: passing it made the writer latch onto its final
///    line and reopen each beat by restating that line verbatim.
/// 6. INSTRUCTION at recency — write the current beat to its word
///    target, open at the next moment of the scene, end on a clean
///    sentence.
///
/// Instruction-at-recency mirrors `BeatGeneration.buildBeatPrompt`
/// (Phase 7). The string is instruct-template-agnostic; the
/// coordinator wraps it for the writer model at request time.
public enum SceneDraftPrompt {

    /// Prior prose embedded in a beat prompt is capped to this many
    /// trailing words. Long enough for the writer to pick up voice and
    /// immediate situation, short enough that there is no whole "prose
    /// so far" body for it to continue *inside* of — the BEAT PLAN
    /// carries the running summary instead.
    static let priorProseTailWords = 60

    public static func buildBeatPrompt(
        sceneSummary: String,
        beats: [SceneBeatPlanning.PlannedBeat],
        currentBeatIndex: Int,
        priorProse: String,
        styles: [Style]
    ) -> String {
        guard currentBeatIndex >= 0, currentBeatIndex < beats.count else {
            return ""
        }
        let beat = beats[currentBeatIndex]
        let isFinal = currentBeatIndex == beats.count - 1
        let hasPrior = !priorProse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let styleText = StylePrompt.render(styles)
        let styleBlock = styleText.isEmpty ? "" : "\n\n\(styleText)"

        let planLines = beats.map { b -> String in
            let marker = b.index == currentBeatIndex ? "  <-- CURRENT" : ""
            return "Beat \(b.index + 1) (~\(b.targetWords) words): \(b.intent)\(marker)"
        }.joined(separator: "\n")

        let seamSection: String
        if hasPrior {
            seamSection = """


            [WHERE THE PREVIOUS BEAT LEFT OFF — for voice continuity only; this ground is already on the page, do not retread it]
            \(tail(of: priorProse))
            """
        } else {
            seamSection = ""
        }

        let openingInstruction = hasPrior
            ? "Open the CURRENT beat at the next moment of the scene — a fresh sentence that carries the action onward. The previous beat is finished; its closing line is already written, so start past it."
            : "This is the scene's opening — establish it from the first line."

        let endingInstruction = isFinal
            ? "This is the final beat — bring the scene to a close on a clean sentence boundary."
            : "End on a clean sentence boundary that leads into the next beat."

        return """
        [SYSTEM]
        You are a fiction writer drafting one scene beat by beat. Write ONLY the prose for the beat marked CURRENT — not the whole scene, not the later beats. Output prose only: no headers, no labels, no commentary, no bracketed blocks.\(styleBlock)

        [SCENE]
        \(sceneSummary)

        [BEAT PLAN]
        \(planLines)\(seamSection)

        [INSTRUCTION]
        Write the CURRENT beat: \(beat.intent)
        Target length: about \(beat.targetWords) words. \(openingInstruction) \(endingInstruction)
        """
    }

    /// The trailing `priorProseTailWords` words of `prose`. When the
    /// prose is longer than the cap the slice is prefixed with `…` so
    /// the writer sees it as a fragment, not a passage to extend.
    private static func tail(of prose: String) -> String {
        let trimmed = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count > priorProseTailWords else { return trimmed }
        return "… " + words.suffix(priorProseTailWords).joined(separator: " ")
    }
}
