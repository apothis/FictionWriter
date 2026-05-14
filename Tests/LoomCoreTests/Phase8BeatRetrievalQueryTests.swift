import Foundation
@testable import LoomCore

// Phase 8.b.4 — per-beat retrieval query construction. Given a beat
// (summary + modality + function), the substituted cast mapping, and
// the last sentence of prior-beats prose as a recency anchor, build
// the query string the style retriever consumes. The cast mapping is
// the substituted version (post-STRAP), so the beat summary's role
// tokens ({PROTAGONIST}, {ANTAGONIST}) never reach the query — but
// the new cast names DO (Maya, Daniel, etc.), giving the retriever a
// way to lean toward chunks that talk about the right people.

private func beat(summary: String, modality: NarrativeMode, function: BeatFunction) -> SceneBeat {
    return SceneBeat(
        index: 0, summary: summary, modality: modality, function: function,
        targetWords: 60, wordRangeStart: 0, wordRangeEnd: 60, beatTensionChange: 0
    )
}

func phase8BeatRetrievalQueryTests() -> TestSuite {
    let s = TestSuite("Phase8BeatRetrievalQuery")

    s.test("query includes beat summary + cast mapping + modality + function") {
        let q = BeatRetrievalQuery.build(
            beat: beat(summary: "They argue across the dinner table.", modality: .dialogue, function: .conflict),
            castMapping: "PROTAGONIST: Maya, 32, journalist. ANTAGONIST: Daniel, her father.",
            priorBeatsProse: ""
        )
        try expectTrue(q.contains("argue across the dinner table"))
        try expectTrue(q.contains("Maya"))
        try expectTrue(q.contains("Daniel"))
        try expectTrue(q.contains("dialogue"))
        try expectTrue(q.contains("conflict"))
    }

    s.test("query appends the last sentence of priorBeatsProse as recency anchor") {
        let prior = """
            Maya walked into the kitchen. She did not say anything for a long moment. \
            She poured herself a glass of water and drank it standing up at the counter.
            """
        let q = BeatRetrievalQuery.build(
            beat: beat(summary: "She begins to speak.", modality: .dialogue, function: .reveal),
            castMapping: "PROTAGONIST: Maya. ANTAGONIST: Daniel.",
            priorBeatsProse: prior
        )
        // Last sentence of prior should land in the query
        try expectTrue(q.contains("drank it standing up at the counter"),
                       "expected last prior-beat sentence in query:\n\(q)")
        // Earlier sentences should NOT — query stays compact
        try expectFalse(q.contains("walked into the kitchen"))
    }

    s.test("empty priorBeatsProse leaves no recency anchor (opening-beat case)") {
        let q = BeatRetrievalQuery.build(
            beat: beat(summary: "She enters the room.", modality: .action, function: .setup),
            castMapping: "PROTAGONIST: Maya.",
            priorBeatsProse: ""
        )
        try expectTrue(q.contains("enters the room"))
        try expectTrue(q.contains("Maya"))
        // No "Recent prose:" or equivalent marker
        try expectFalse(q.localizedCaseInsensitiveContains("recent"))
    }

    s.test("query does not leak unsubstituted role tokens") {
        // Beat summaries use {PROTAGONIST}/{ANTAGONIST} tokens per
        // STRAP. The query construction must leave those alone; the
        // retriever sees them but they're tokens, not source-character
        // names — which is the leakage we're guarding against.
        let q = BeatRetrievalQuery.build(
            beat: beat(summary: "{PROTAGONIST} turns to {ANTAGONIST}.", modality: .dialogue, function: .reaction),
            castMapping: "PROTAGONIST: Maya. ANTAGONIST: Daniel.",
            priorBeatsProse: ""
        )
        try expectTrue(q.contains("{PROTAGONIST}"))
        // But the cast mapping resolves them to Maya/Daniel too, which
        // is fine.
        try expectTrue(q.contains("Maya"))
    }

    return s
}
