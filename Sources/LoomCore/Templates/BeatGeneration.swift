import Foundation

/// Phase 7.a.2 — Pass-B per-beat generation prompt assembly.
///
/// Built once per beat (M beats per scene → M calls). The prompt
/// is structured so a writer LLM (Kobold/gemma-4-31B in production)
/// generates `targetWords` words of prose for the current beat, in
/// the modality + function specified by the Pass-A skeleton, with the
/// template scene present as a voice exemplar (NOT as a content
/// donor — D4 STRAP framing).
///
/// Layer order (top-to-bottom; instruction at recency per
/// [Liu et al. "Lost in the Middle" TACL 2024](https://arxiv.org/abs/2307.03172)):
///
/// 1. SYSTEM framing (writer role + the "template is voice exemplar
///    only, do not reuse plot" guard rail)
/// 2. TEMPLATE SCENE body (middle of prompt — structural reference,
///    not load-bearing for attention since the skeleton is the
///    real structural signal; explicitly framed as voice-only)
/// 3. BEAT SKELETON (the full M-beat list with function + modality +
///    target words + summary — the load-bearing structural signal,
///    placed near recency)
/// 4. NEW CAST mapping (free-form v1; structured table in v2)
/// 5. PACING TARGET for current beat (positive numerical constraints
///    per D6)
/// 6. PRIOR-BEAT prose (beats 1..N-1 already generated — gives the
///    writer the running scene continuity)
/// 7. INSTRUCTION at the very end: "Write beat N. Modality: M. Target
///    length: T words. End at a natural sentence boundary."
///
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md) §7.2.
public enum BeatGeneration {

    public static func buildBeatPrompt(
        templateBody: String,
        skeleton: ExtractedSceneSkeleton,
        castMapping: String,
        currentBeatIndex: Int,
        priorBeatsProse: String,
        groundTruthPacing: PacingStats,
        includeTemplateBody: Bool = true
    ) -> String {
        // Bounds-check the index — out-of-range returns empty so the
        // caller fails loudly (the spike runner catches + logs).
        guard currentBeatIndex >= 0, currentBeatIndex < skeleton.beats.count else {
            return ""
        }
        let beat = skeleton.beats[currentBeatIndex]
        let isLastBeat = currentBeatIndex == skeleton.beats.count - 1

        // Skeleton listing — beats 0..currentBeatIndex with full
        // summary; current beat marked. Future beats (N+1..M) are
        // NOT shown by full summary per Phase 7.b prompt-revision
        // punchlist item 1 — in §7.a.2 the model echoed beat N+1's
        // skeleton line verbatim into beat N's output. A short
        // "next beat will be ..." hint is appended separately so the
        // model still knows where to land the transition.
        var skeletonLines: [String] = []
        for (i, b) in skeleton.beats.enumerated() where i <= currentBeatIndex {
            let marker = (i == currentBeatIndex) ? " <-- CURRENT" : ""
            skeletonLines.append(
                "Beat \(i) (\(b.function.rawValue), \(b.modality.rawValue), target \(b.targetWords) words): \(b.summary)\(marker)"
            )
        }
        let skeletonBlock = skeletonLines.joined(separator: "\n")

        // Future-beat hint: function + modality + target only, no
        // plot summary. Only present when there IS a next beat.
        let nextBeatHint: String
        let nextIdx = currentBeatIndex + 1
        if nextIdx < skeleton.beats.count {
            let next = skeleton.beats[nextIdx]
            nextBeatHint = "\n\n[NEXT-BEAT HINT — do not write it, just land your ending so it can follow]\nThe next beat (beat \(nextIdx)) will be a \(next.function.rawValue) in \(next.modality.rawValue) modality, roughly \(next.targetWords) words long. The current beat should end at a sentence boundary that flows into that."
        } else {
            nextBeatHint = ""
        }

        // Pacing target — positive numerical (D6). Uses the ground-truth
        // computed pacing rather than the LLM-reported one (per 7.a.1
        // finding §1.4-3).
        let pacingLine = String(format:
            "Mean sentence length %.1f words (σ %.1f). About %.0f%% of sentences should be short (under 8 words); about %.0f%% should be long (over 20 words). Dialogue ratio target: %.0f%%.",
            groundTruthPacing.meanSentenceLengthWords,
            groundTruthPacing.sentenceLengthStdDev,
            groundTruthPacing.shortSentenceRatio * 100,
            groundTruthPacing.longSentenceRatio * 100,
            groundTruthPacing.dialogueRatio * 100
        )

        let endingInstruction = isLastBeat
            ? "End the scene at a natural sentence boundary. This is the final beat."
            : "End at a natural sentence boundary that leads into the next beat."

        let priorBeatsSection: String
        if priorBeatsProse.isEmpty {
            priorBeatsSection = "[BEATS BEFORE THIS — no prior beats yet; this is the opening]"
        } else {
            priorBeatsSection = """
                [BEATS BEFORE THIS — already generated, do not regenerate]
                \(priorBeatsProse)
                """
        }

        // Phase 7.b followup — voice-descriptor injection at recency.
        // The §7.a.3 ablation showed voice transfer is the design's
        // weakest leg; the mitigation is to extract a focused voice
        // fingerprint at Pass A and inject it here as explicit
        // positive constraints, immediately before the per-beat
        // instruction. Renders nothing when the descriptor is absent
        // (legacy sidecars).
        let voiceTargetBlock: String
        if let v = skeleton.voiceDescriptor {
            let bullets = v.distinctiveTechniques
                .map { "  - \($0)" }
                .joined(separator: "\n")
            voiceTargetBlock = """

                [VOICE TARGET — match these specific voice qualities; treat as positive constraints, not as suggestions]
                - Sentence cadence: \(voiceCadenceHint(v.sentenceCadence))
                - Dialogue density: \(voiceDialogueHint(v.dialogueDensity))
                - Rhetorical flourish: \(voiceFlourishHint(v.rhetoricalFlourish))
                - Register: \(v.register)
                - Distinctive techniques (apply each consistently in this beat):
                \(bullets)
                """
        } else {
            voiceTargetBlock = ""
        }

        // The whole prompt is collapsed into a single instruct-template-agnostic
        // string — the production GenerationCoordinator wraps it in the
        // model's chat template (chatml / gemma / etc.) at request time.
        // For the spike runner we use raw completion.
        let systemFraming: String
        let templateBlock: String
        if includeTemplateBody {
            systemFraming = """
                [SYSTEM]
                You are a fiction writer. Your job is to write ONE beat of a scene whose structural skeleton is given below. Follow the current beat's modality, function, and target word count precisely. Do NOT write the whole scene — only the one beat marked CURRENT.

                The TEMPLATE SCENE below is provided as a VOICE EXEMPLAR — study its prose voice, sentence rhythm, register, and modality handling. Do NOT reuse its plot, characters, settings, or specific events. The new scene's content comes from the NEW CAST mapping. The template is showing you HOW to write, not WHAT to write.
                """
            templateBlock = """
                === TEMPLATE SCENE (voice reference; do not reuse plot) ===
                \(templateBody)
                === END TEMPLATE SCENE ===


                """
        } else {
            // Ablation arm B: skeleton-only. No template prose, no
            // voice-exemplar framing. Writer infers voice from the
            // skeleton's summaries + the pacing target alone.
            systemFraming = """
                [SYSTEM]
                You are a fiction writer. Your job is to write ONE beat of a scene whose structural skeleton is given below. Follow the current beat's modality, function, and target word count precisely. Do NOT write the whole scene — only the one beat marked CURRENT. The new scene's content comes from the NEW CAST mapping.
                """
            templateBlock = ""
        }

        return """
            \(systemFraming)

            \(templateBlock)[BEAT SKELETON — current and past beats only — \(skeleton.beats.count) beats total in the scene]
            \(skeletonBlock)\(nextBeatHint)

            [NEW CAST]
            \(castMapping)

            [PACING TARGET FOR THIS BEAT]
            \(pacingLine)

            \(priorBeatsSection)
            \(voiceTargetBlock)

            [INSTRUCTION]
            Write beat \(currentBeatIndex). Modality: \(beat.modality.rawValue). Function: \(beat.function.rawValue). Target length: \(beat.targetWords) words. \(endingInstruction)

            Beat \(currentBeatIndex) prose:
            """
    }

    // MARK: - Voice-descriptor hints

    /// Expand the cadence enum into a concrete instruction. The
    /// writer LLM responds more reliably to descriptive language
    /// than to enum tokens — "short, clipped sentences (under 8
    /// words; bare declaratives; subject-verb-object)" beats
    /// "shortClipped".
    private static func voiceCadenceHint(_ c: SentenceCadence) -> String {
        switch c {
        case .shortClipped:
            return "short, clipped sentences. Aim for bare declaratives; subject-verb-object; few or no subordinate clauses; most sentences under 10 words."
        case .moderateBalanced:
            return "balanced mix of short and long sentences; moderate use of subordinate clauses."
        case .longFlowing:
            return "long, periodic sentences with nested subordinate clauses; rhythm should build over commas / semicolons; Conrad-adjacent."
        }
    }

    private static func voiceDialogueHint(_ d: DialogueDensity) -> String {
        switch d {
        case .dialogueHeavy:
            return "dialogue-heavy. Lean on direct speech; minimal narration between exchanges."
        case .balanced:
            return "balanced narration and dialogue."
        case .narrativeHeavy:
            return "narration-heavy. Dialogue should be sparse or absent in this beat."
        }
    }

    private static func voiceFlourishHint(_ f: RhetoricalFlourish) -> String {
        switch f {
        case .minimal:
            return "minimal. NO metaphor, NO rhetorical adornment, NO adverbial qualification. Concrete nouns and active verbs only."
        case .moderate:
            return "moderate. Occasional figurative language; image and sensory detail used purposefully but not lavishly."
        case .ornate:
            return "ornate. Lyrical, image-dense prose; metaphor and rhythm in the foreground."
        }
    }
}
