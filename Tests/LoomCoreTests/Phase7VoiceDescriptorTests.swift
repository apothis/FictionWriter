import Foundation
@testable import LoomCore

/// Phase 7.b followup — voice-descriptor extraction + injection.
///
/// Driven by §7.a.3's empirical finding that voice transfer is the
/// design's weakest leg — both arms (template-included vs skeleton-
/// only) produce gemma-default writerly prose, not the template's
/// surface voice. The proposed mitigation is an explicit voice-
/// descriptor field that Pass A extracts and Pass B injects at
/// recency as a positive constraint (per the §7.a.3 D6 finding
/// that explicit constraints outperform implicit imitation).
///
/// Pinned in [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) §3.8
/// (the v2 voice-weight dial was deferred in favor of this approach).
func phase7VoiceDescriptorTests() -> TestSuite {
    let s = TestSuite("Phase7VoiceDescriptor")

    // MARK: - VoiceDescriptor model

    s.test("VoiceDescriptor round-trips Codable with all fields") {
        let v = VoiceDescriptor(
            sentenceCadence: .shortClipped,
            dialogueDensity: .dialogueHeavy,
            rhetoricalFlourish: .minimal,
            register: "Hemingway-clipped",
            distinctiveTechniques: [
                "Single-line dialogue exchanges with bare 'he said' attribution",
                "Subject-verb-object sentence structure with no subordinate clauses",
                "Repetition of key concrete nouns to build pressure",
            ]
        )
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(VoiceDescriptor.self, from: data)
        try expectEqual(decoded, v)
    }

    s.test("VoiceDescriptor.allEnumCases produce the expected raw values") {
        // The Pass-A schema uses these raw values as the enum
        // constraint passed to Ollama; if a case is renamed, the
        // schema's `enum:` list drifts silently. Pin them here.
        try expectEqual(
            Set(SentenceCadence.allCases.map(\.rawValue)),
            Set(["shortClipped", "moderateBalanced", "longFlowing"])
        )
        try expectEqual(
            Set(DialogueDensity.allCases.map(\.rawValue)),
            Set(["dialogueHeavy", "balanced", "narrativeHeavy"])
        )
        try expectEqual(
            Set(RhetoricalFlourish.allCases.map(\.rawValue)),
            Set(["minimal", "moderate", "ornate"])
        )
    }

    // MARK: - ExtractedSceneSkeleton.voiceDescriptor

    s.test("ExtractedSceneSkeleton round-trips with optional voiceDescriptor") {
        let withVoice = ExtractedSceneSkeleton(
            beats: [], sourceCharacters: [], sourceSettingMarkers: [],
            voiceDescriptor: VoiceDescriptor(
                sentenceCadence: .longFlowing,
                dialogueDensity: .narrativeHeavy,
                rhetoricalFlourish: .ornate,
                register: "Conrad-adjacent periodic prose",
                distinctiveTechniques: ["nested subordinate clauses"]
            )
        )
        let data = try JSONEncoder().encode(withVoice)
        let decoded = try JSONDecoder().decode(ExtractedSceneSkeleton.self, from: data)
        try expectEqual(decoded.voiceDescriptor?.register, "Conrad-adjacent periodic prose")
    }

    s.test("ExtractedSceneSkeleton decodes legacy sidecar without voiceDescriptor") {
        // Phase 7.b sidecars that escaped pre-voice-descriptor must
        // still load — this is the back-compat decode path.
        let legacy = """
        {
          "beats": [],
          "sourceCharacters": ["x"],
          "sourceSettingMarkers": []
        }
        """
        let decoded = try JSONDecoder().decode(
            ExtractedSceneSkeleton.self, from: legacy.data(using: .utf8)!
        )
        try expectEqual(decoded.sourceCharacters, ["x"])
        try expectTrue(decoded.voiceDescriptor == nil)
    }

    // MARK: - BeatExtraction prompt + schema

    s.test("BeatExtraction.buildExtractionPrompt asks for voiceDescriptor") {
        let prompt = BeatExtraction.buildExtractionPrompt(sourceProse: "She walked.")
        try expectTrue(prompt.contains("voiceDescriptor"))
        try expectTrue(prompt.lowercased().contains("voice"))
        // The Pass-A prompt must enumerate the structured fields so
        // gemma4_2b knows the enum value space.
        try expectTrue(prompt.contains("sentenceCadence"))
        try expectTrue(prompt.contains("shortClipped"))
        try expectTrue(prompt.contains("distinctiveTechniques"))
    }

    s.test("BeatExtraction.jsonSchema includes voiceDescriptor with enum constraints") {
        let schema = BeatExtraction.jsonSchema()
        let props = schema["properties"] as! [String: Any]
        let voiceSchema = props["voiceDescriptor"] as! [String: Any]
        let voiceProps = voiceSchema["properties"] as! [String: Any]
        let cadence = voiceProps["sentenceCadence"] as! [String: Any]
        let cadenceEnum = cadence["enum"] as! [String]
        try expectEqual(Set(cadenceEnum), Set(SentenceCadence.allCases.map(\.rawValue)))
        // The schema must put voiceDescriptor in required so Ollama
        // produces it for new extractions.
        let required = schema["required"] as! [String]
        try expectTrue(required.contains("voiceDescriptor"))
    }

    // MARK: - BeatGeneration prompt injection

    func skeletonWithVoice(_ v: VoiceDescriptor?) -> ExtractedSceneSkeleton {
        ExtractedSceneSkeleton(
            beats: [
                SceneBeat(
                    index: 0, summary: "{PROTAGONIST} arrives.",
                    modality: .action, function: .arrival,
                    targetWords: 80, wordRangeStart: 0, wordRangeEnd: 80,
                    beatTensionChange: 1
                ),
            ],
            sourceCharacters: ["Mara"], sourceSettingMarkers: ["doorway"],
            voiceDescriptor: v
        )
    }

    s.test("BeatGeneration.buildBeatPrompt injects [VOICE TARGET] block when descriptor present") {
        let v = VoiceDescriptor(
            sentenceCadence: .shortClipped,
            dialogueDensity: .dialogueHeavy,
            rhetoricalFlourish: .minimal,
            register: "Hemingway-clipped",
            distinctiveTechniques: ["Bare 'he said' tags only"]
        )
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T", skeleton: skeletonWithVoice(v),
            castMapping: "C", currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: PacingStats.zero
        )
        try expectTrue(prompt.contains("VOICE TARGET")
                    || prompt.contains("Voice target"))
        // The descriptor's key signals appear in the prompt.
        try expectTrue(prompt.contains("Hemingway-clipped"))
        try expectTrue(prompt.contains("short"))   // sentenceCadence
        try expectTrue(prompt.contains("minimal")) // rhetoricalFlourish
        try expectTrue(prompt.contains("Bare 'he said'"))
    }

    s.test("BeatGeneration.buildBeatPrompt omits [VOICE TARGET] when descriptor absent") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T", skeleton: skeletonWithVoice(nil),
            castMapping: "C", currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: PacingStats.zero
        )
        try expectFalse(prompt.contains("VOICE TARGET"))
        try expectFalse(prompt.contains("Voice target"))
    }

    s.test("BeatGeneration.buildBeatPrompt places [VOICE TARGET] near recency, after prior beats") {
        let v = VoiceDescriptor(
            sentenceCadence: .moderateBalanced,
            dialogueDensity: .balanced,
            rhetoricalFlourish: .moderate,
            register: "test-register-MARKER",
            distinctiveTechniques: ["x"]
        )
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T", skeleton: skeletonWithVoice(v),
            castMapping: "MAPPING-MARKER",
            currentBeatIndex: 0,
            priorBeatsProse: "PRIOR-PROSE-MARKER",
            groundTruthPacing: PacingStats.zero
        )
        // Voice target must come AFTER the cast mapping (so it's
        // closer to the recency slot at the end of the prompt where
        // the instruction lives).
        guard let voiceIdx = prompt.range(of: "test-register-MARKER")?.lowerBound,
              let castIdx = prompt.range(of: "MAPPING-MARKER")?.lowerBound,
              let instrIdx = prompt.range(of: "[INSTRUCTION]")?.lowerBound
        else {
            try expectFalse(true, "missing expected markers in prompt")
            return
        }
        try expectTrue(castIdx < voiceIdx, "voice target should come after cast mapping")
        try expectTrue(voiceIdx < instrIdx, "voice target should come before the instruction")
    }

    return s
}
