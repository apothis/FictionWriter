import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, subject resolution. A claim's
/// `subject` is free text as the LLM wrote it; grounding it to a
/// canonical entity name keeps conflict retrieval from fragmenting one
/// entity ("Mara" / "Mara Vance") across several groups.
func continuitySubjectResolverTests() -> TestSuite {
    let s = TestSuite("ContinuitySubjectResolver")

    let entities = [
        ContinuitySubjectResolver.KnownEntity(name: "Mara Vance", aliases: ["Mara"]),
        ContinuitySubjectResolver.KnownEntity(name: "Lighthouse", aliases: ["the old tower"]),
    ]

    func claim(subject: String) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .attribute, subject: subject, attributeKey: "k", value: "v",
            sourceSceneId: "s1", source: .narration, evidenceQuote: "q"
        )
    }

    s.test("a subject matching an entity name resolves to that name") {
        try expectEqual(
            ContinuitySubjectResolver.resolve(subject: "Mara Vance", entities: entities),
            "Mara Vance")
    }

    s.test("a subject matching an alias resolves to the canonical name") {
        try expectEqual(
            ContinuitySubjectResolver.resolve(subject: "Mara", entities: entities),
            "Mara Vance")
    }

    s.test("resolution is case- and article-insensitive") {
        try expectEqual(
            ContinuitySubjectResolver.resolve(subject: "the LIGHTHOUSE", entities: entities),
            "Lighthouse")
        try expectEqual(
            ContinuitySubjectResolver.resolve(subject: "The Old Tower", entities: entities),
            "Lighthouse")
    }

    s.test("an unresolved subject falls back to its normalised surface form") {
        try expectEqual(
            ContinuitySubjectResolver.resolve(subject: "The Innkeeper", entities: entities),
            "innkeeper")
    }

    s.test("ground rewrites every claim's subject to its resolved form") {
        let grounded = ContinuitySubjectResolver.ground(
            claims: [claim(subject: "Mara"), claim(subject: "Mara Vance"), claim(subject: "a stranger")],
            entities: entities
        )
        try expectEqual(grounded[0].subject, "Mara Vance")
        try expectEqual(grounded[1].subject, "Mara Vance")
        try expectEqual(grounded[2].subject, "stranger")
    }

    s.test("grounding rewrites a subject referred to two ways to one canonical form") {
        let grounded = ContinuitySubjectResolver.ground(
            claims: [
                ContinuityAudit.Claim(type: .attribute, subject: "Mara", attributeKey: "eye colour",
                                      value: "Mara has green eyes", sourceSceneId: "s1", source: .narration, evidenceQuote: "q"),
                ContinuityAudit.Claim(type: .attribute, subject: "Mara Vance", attributeKey: "eye colour",
                                      value: "Mara has brown eyes", sourceSceneId: "s2", source: .narration, evidenceQuote: "q"),
            ],
            entities: entities
        )
        try expectEqual(grounded[0].subject, grounded[1].subject)
        try expectEqual(grounded[0].subject, "Mara Vance")
    }

    return s
}
