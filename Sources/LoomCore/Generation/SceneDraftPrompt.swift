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
/// 4. BEAT PLAN — every beat's intent, the current one marked.
/// 5. PRIOR PROSE — the beats already drafted (running continuity).
/// 6. INSTRUCTION at recency — write the current beat to its word
///    target, continue from the prose above, end on a clean sentence.
///
/// Instruction-at-recency mirrors `BeatGeneration.buildBeatPrompt`
/// (Phase 7). The string is instruct-template-agnostic; the
/// coordinator wraps it for the writer model at request time.
public enum SceneDraftPrompt {

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

        let styleText = StylePrompt.render(styles)
        let styleBlock = styleText.isEmpty ? "" : "\n\n\(styleText)"

        let planLines = beats.map { b -> String in
            let marker = b.index == currentBeatIndex ? "  <-- CURRENT" : ""
            return "Beat \(b.index + 1) (~\(b.targetWords) words): \(b.intent)\(marker)"
        }.joined(separator: "\n")

        let priorSection: String
        if priorProse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            priorSection = "[PROSE SO FAR — none; the current beat is the scene's opening]"
        } else {
            priorSection = """
            [PROSE SO FAR — already written, do not repeat or rephrase it]
            \(priorProse)
            """
        }

        let endingInstruction = isFinal
            ? "This is the final beat — bring the scene to a close on a clean sentence boundary."
            : "End on a clean sentence boundary that leads into the next beat."

        return """
        [SYSTEM]
        You are a fiction writer drafting one scene beat by beat. Write ONLY the prose for the beat marked CURRENT — not the whole scene, not the later beats. Output prose only: no headers, no labels, no commentary, no bracketed blocks.\(styleBlock)

        [SCENE]
        \(sceneSummary)

        [BEAT PLAN]
        \(planLines)

        \(priorSection)

        [INSTRUCTION]
        Write the CURRENT beat: \(beat.intent)
        Target length: about \(beat.targetWords) words. Continue directly from the prose so far. \(endingInstruction)
        """
    }
}
