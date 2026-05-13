import Foundation
@testable import LoomCore

/// Pure-data tests for the narrative-mode taxonomy used by Phase 5
/// scope-lock #5 (per-scene-type retrieval). Six modes:
/// {action, dialogue, interiority, description, summary, mixed},
/// extended from LOOM_RESEARCH.md §O.4's original four after the
/// 2026-05-13 pre-spike research surfaced summary as a load-bearing
/// missing category (Marshall 1998 / Card 1999 / Le Guin
/// *Steering the Craft* — scene-vs-summary is the orthogonal pace
/// axis). See LOOM_NARRATIVE_MODE_SPIKE.md §2.
func phase5NarrativeModeTests() -> TestSuite {
    let s = TestSuite("Phase5NarrativeMode")

    s.test("NarrativeMode enum has the 6 documented values") {
        let all = NarrativeMode.allCases
        try expectEqual(Set(all), Set([
            .action, .dialogue, .interiority, .description, .summary, .mixed
        ]))
    }

    s.test("NarrativeMode.rawValue is the lowercase identifier (matches GBNF grammar)") {
        try expectEqual(NarrativeMode.action.rawValue, "action")
        try expectEqual(NarrativeMode.dialogue.rawValue, "dialogue")
        try expectEqual(NarrativeMode.interiority.rawValue, "interiority")
        try expectEqual(NarrativeMode.description.rawValue, "description")
        try expectEqual(NarrativeMode.summary.rawValue, "summary")
        try expectEqual(NarrativeMode.mixed.rawValue, "mixed")
    }

    s.test("NarrativeMode round-trips via rawValue (LLM output parse path)") {
        for mode in NarrativeMode.allCases {
            let parsed = NarrativeMode(rawValue: mode.rawValue)
            try expectEqual(parsed, mode)
        }
    }

    s.test("NarrativeMode rejects unknown labels") {
        try expectNil(NarrativeMode(rawValue: "narrative"))
        try expectNil(NarrativeMode(rawValue: "ACTION"))      // case-sensitive
        try expectNil(NarrativeMode(rawValue: "exposition"))  // not in v1 taxonomy
        try expectNil(NarrativeMode(rawValue: ""))
    }

    s.test("NarrativeMode.gbnfAlternation produces the flat-enum grammar fragment") {
        // The flat-enum grammar that gemma-31B's GBNF will use.
        // Format: "action" | "dialogue" | ... — exactly the form
        // that dodged Path C's nested-JSON collapse failure mode
        // ("Lost in Space" 2025).
        let g = NarrativeMode.gbnfAlternation
        try expectTrue(g.contains("\"action\""))
        try expectTrue(g.contains("\"dialogue\""))
        try expectTrue(g.contains("\"interiority\""))
        try expectTrue(g.contains("\"description\""))
        try expectTrue(g.contains("\"summary\""))
        try expectTrue(g.contains("\"mixed\""))
        try expectTrue(g.contains("|"))
    }

    s.test("ReferenceTextIndex.Chunk.modality accepts every NarrativeMode rawValue") {
        // The existing schema slot is `String?`; the spike formalises
        // its value space via NarrativeMode. Pins that the existing
        // Chunk type round-trips every typed value as its rawValue.
        for mode in NarrativeMode.allCases {
            let chunk = ReferenceTextIndex.Chunk(
                text: "test",
                wordRangeStart: 0,
                wordRangeEnd: 1,
                modality: mode.rawValue
            )
            let data = try JSONEncoder.loomPretty.encode(chunk)
            let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.Chunk.self, from: data)
            try expectEqual(decoded.modality, mode.rawValue)
            try expectEqual(NarrativeMode(rawValue: decoded.modality ?? ""), mode)
        }
    }

    return s
}
