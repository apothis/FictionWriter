import Foundation

/// Phase 7.b followup — explicit voice fingerprint extracted from a
/// template scene at Pass A time, injected into Pass B at recency
/// as a positive constraint.
///
/// Motivated by [`LOOM_SCENE_TEMPLATE_SPIKE.md`](../../../LOOM_SCENE_TEMPLATE_SPIKE.md)
/// §3 — across two A/B fixtures, the template prose itself acted as
/// a task anchor but did NOT meaningfully transfer surface voice. The
/// writer produced gemma-default writerly register regardless of
/// whether Hemingway-clipped or Conrad-periodic prose was in the
/// prompt. The hypothesis: explicit positive constraints outperform
/// implicit imitation (matches the §7.a.3 D6 finding on pacing).
///
/// Five fields: three constrained enums (the model can't
/// hallucinate values), one short free-form `register` phrase, one
/// bulleted `distinctiveTechniques` list. Compact enough to inject
/// at recency without burning the prompt budget.
public struct VoiceDescriptor: Codable, Equatable {
    public var sentenceCadence: SentenceCadence
    public var dialogueDensity: DialogueDensity
    public var rhetoricalFlourish: RhetoricalFlourish
    /// A short phrase characterising the voice. Free-form so the
    /// model can use whatever vocabulary fits — "noir minimalism",
    /// "Conrad-adjacent periodic prose", "Cormac McCarthy biblical",
    /// "Victorian three-decker", etc.
    public var register: String
    /// 2–5 bullet points naming specific craft moves the prose uses
    /// (e.g. "single-line dialogue with bare 'he said' tags only",
    /// "subject-verb-object sentence structure exclusively",
    /// "repetition of concrete nouns to build pressure"). These are
    /// the most surgically useful signals for Pass B — they tell the
    /// writer what specific things to DO.
    public var distinctiveTechniques: [String]

    public init(
        sentenceCadence: SentenceCadence,
        dialogueDensity: DialogueDensity,
        rhetoricalFlourish: RhetoricalFlourish,
        register: String,
        distinctiveTechniques: [String]
    ) {
        self.sentenceCadence = sentenceCadence
        self.dialogueDensity = dialogueDensity
        self.rhetoricalFlourish = rhetoricalFlourish
        self.register = register
        self.distinctiveTechniques = distinctiveTechniques
    }
}

/// Constrained cadence categories. The enum constrains Ollama's
/// `format` parameter so the model can't emit free-form noise here.
public enum SentenceCadence: String, Codable, CaseIterable, Equatable {
    /// Hemingway / Carver / Lydia Davis — bare declaratives,
    /// short clauses, no subordination.
    case shortClipped
    /// The default mode for most prose. Mix of short and long.
    case moderateBalanced
    /// Conrad / Faulkner / McCarthy — periodic sentences with
    /// nested subordinate clauses; rhythm builds over multiple
    /// commas / semicolons.
    case longFlowing
}

public enum DialogueDensity: String, Codable, CaseIterable, Equatable {
    case dialogueHeavy
    case balanced
    case narrativeHeavy
}

public enum RhetoricalFlourish: String, Codable, CaseIterable, Equatable {
    /// No metaphor, no rhetorical adornment, no adverbial qualification.
    case minimal
    case moderate
    /// Lyrical / ornate / image-dense.
    case ornate
}
