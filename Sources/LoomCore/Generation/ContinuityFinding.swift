import Foundation

/// Continuity Audit (L10) — Phase B, the `ContinuityFinding` type and
/// finding assembly.
///
/// A finding is one reviewable continuity error: the conflicting claim
/// pair, an explanation, a severity, and a review status. Findings are
/// what the writer triages — never auto-applied.
public struct ContinuityFinding: Codable, Equatable, Identifiable {

    /// Which audited class the finding belongs to.
    public enum Kind: String, Codable, Equatable, CaseIterable {
        case attributeDrift = "attribute_drift"
        case knowledgeViolation = "knowledge_violation"
        case timelineConflict = "timeline_conflict"
        case spatialConflict = "spatial_conflict"
    }

    public enum Severity: String, Codable, Equatable, CaseIterable {
        case high
        case medium
        case low
    }

    /// The writer's triage state for the finding.
    public enum Status: String, Codable, Equatable, CaseIterable {
        case open
        case dismissed
        case resolved
    }

    public var id: UUID
    public var kind: Kind
    public var severity: Severity
    /// The earlier claim (or, for a knowledge violation, the reference).
    public var claimA: ContinuityAudit.Claim
    /// The later claim (or, for a knowledge violation, the reveal).
    public var claimB: ContinuityAudit.Claim
    public var explanation: String
    /// 0…1 — confidence the finding is a real error.
    public var confidence: Double
    public var status: Status

    public init(
        id: UUID = UUID(),
        kind: Kind,
        severity: Severity,
        claimA: ContinuityAudit.Claim,
        claimB: ContinuityAudit.Claim,
        explanation: String,
        confidence: Double,
        status: Status = .open
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.claimA = claimA
        self.claimB = claimB
        self.explanation = explanation
        self.confidence = confidence
        self.status = status
    }
}

/// Turns adjudication verdicts and knowledge-state violations into
/// `ContinuityFinding`s. Pure data.
public enum ContinuityFindingAssembly {

    /// A finding for an adjudicated candidate pair — `nil` unless the
    /// verdict is `contradiction` (a `consistent` or `evolution` pair
    /// is not an error).
    public static func finding(
        pair: ContinuityConflictRetrieval.CandidatePair,
        adjudication: ContinuityAudit.Adjudication
    ) -> ContinuityFinding? {
        guard adjudication.verdict == .contradiction else { return nil }
        return ContinuityFinding(
            kind: kind(for: pair.earlier.type),
            severity: severity(forConfidence: adjudication.confidence),
            claimA: pair.earlier,
            claimB: pair.later,
            explanation: adjudication.explanation,
            confidence: adjudication.confidence,
            status: .open
        )
    }

    /// A finding for a knowledge-state violation. A character knowing
    /// the unrevealed reads as a hard error, so severity is always
    /// `high`; the detection is deterministic, so confidence is fixed.
    public static func finding(
        knowledgeViolation v: ContinuityKnowledgeCheck.Violation
    ) -> ContinuityFinding {
        let ref = v.knowledgeClaim.sourceSceneId
        let rev = v.revealClaim.sourceSceneId
        return ContinuityFinding(
            kind: .knowledgeViolation,
            severity: .high,
            claimA: v.knowledgeClaim,
            claimB: v.revealClaim,
            explanation: "References this in scene \(ref), but it is first revealed in scene \(rev).",
            confidence: 0.9,
            status: .open
        )
    }

    private static func kind(for type: ContinuityAudit.ClaimType) -> ContinuityFinding.Kind {
        switch type {
        case .spatial: return .spatialConflict
        case .temporal: return .timelineConflict
        case .attribute, .event, .knowledgeState: return .attributeDrift
        }
    }

    private static func severity(forConfidence c: Double) -> ContinuityFinding.Severity {
        if c >= 0.85 { return .high }
        if c >= 0.6 { return .medium }
        return .low
    }
}
