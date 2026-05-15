import Foundation

/// Flat sampler-parameter struct mapping 1:1 to koboldcpp's
/// `/api/v1/generate` body keys. Decoupled from `GenerationDefaults`
/// (the user-visible Loom settings shape) so KoboldClient is a thin
/// HTTP wrapper, not a domain model. The Loom-side mapping
/// (GenerationDefaults → SamplerParams) lives in PromptBuilder when
/// it lands in sub-step 1.i.
public struct SamplerParams: Equatable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var minP: Double
    public var repPen: Double
    public var repPenRange: Int
    public var maxLength: Int
    public var samplerOrder: [Int]
    // Phase 1 contract (LOOM_RESEARCH.md §I.3) ships DRY + XTC alongside
    // basic samplers. Defaults match GenerationDefaults.phase1Defaults.
    public var dryMultiplier: Double
    public var dryBase: Double
    public var dryAllowedLength: Int
    public var xtcThreshold: Double
    public var xtcProbability: Double

    public init(
        temperature: Double = 1.0,
        topP: Double = 0.95,
        topK: Int = 0,
        minP: Double = 0.05,
        repPen: Double = 1.07,
        repPenRange: Int = 1024,
        maxLength: Int = 1024,
        samplerOrder: [Int] = [6, 0, 1, 3, 4, 2, 5],
        dryMultiplier: Double = 0.8,
        dryBase: Double = 1.75,
        dryAllowedLength: Int = 2,
        xtcThreshold: Double = 0.1,
        xtcProbability: Double = 0.5
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repPen = repPen
        self.repPenRange = repPenRange
        self.maxLength = maxLength
        self.samplerOrder = samplerOrder
        self.dryMultiplier = dryMultiplier
        self.dryBase = dryBase
        self.dryAllowedLength = dryAllowedLength
        self.xtcThreshold = xtcThreshold
        self.xtcProbability = xtcProbability
    }

    public static let phase1Defaults = SamplerParams()

    /// Family-specific sampler override applied at request-construction
    /// time. Caller substitutes these three values in over its basis
    /// params (project GenerationDefaults). Returns nil for families
    /// where the existing defaults are already correct.
    public static func familyOverride(forModelName name: String?) -> SamplerFamilyOverride? {
        guard let lower = name?.lowercased(), !lower.isEmpty else { return nil }
        // Mistral-Small-3.x finetune family — community-recommended
        // samplers per MuXodious Harbinger / Magidonia-heresy cards
        // and Drummer Cydonia-v2 / Magidonia-v4.3 discussions.
        if lower.contains("cydonia") || lower.contains("goetia")
            || lower.contains("magidonia") || lower.contains("harbinger")
            || lower.contains("hearthfire") || lower.contains("skyfall")
        {
            return SamplerFamilyOverride(temperature: 0.8, minP: 0.025, repPen: 1.05)
        }
        return nil
    }
}

/// Family-specific sampler override (three values that vary across
/// finetune families — everything else stays at project defaults).
public struct SamplerFamilyOverride: Equatable {
    public let temperature: Double
    public let minP: Double
    public let repPen: Double

    public init(temperature: Double, minP: Double, repPen: Double) {
        self.temperature = temperature
        self.minP = minP
        self.repPen = repPen
    }
}
