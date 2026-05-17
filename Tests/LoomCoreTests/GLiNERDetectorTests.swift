import Foundation
@testable import LoomCore

/// GLiNER native entity detector — phase 4c end-to-end inference.
///
/// The load-bearing check: tokenizer + input construction + the
/// (graph-surgeried) ONNX session + decode, composed, must reproduce
/// the ground-truth fixture's decoded entities exactly. Skips when the
/// gitignored model bundle hasn't been exported locally.
func glinerDetectorTests() -> TestSuite {
    let s = TestSuite("GLiNERDetector")

    s.test("default detection threshold is 0.45") {
        // Lowered from GLiNER's Python default of 0.5: real character
        // names land just under 0.5 on some prose — "Della" scored
        // 0.492 on both mentions in a live scene (§15.27), missing the
        // cutoff by 0.008 while pronoun noise sat far below at ~0.31.
        try expectEqual(GLiNERDetector.defaultThreshold, 0.45)
    }

    s.test("detects the fixture entities end-to-end through the ONNX session") {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gliner_inference_fixture.json")
        guard let data = try? Data(contentsOf: fixtureURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["input_text"] as? String,
              let labels = root["labels"] as? [String],
              let threshold = root["threshold"] as? Double,
              let expected = root["decoded_entities"] as? [[String: Any]]
        else {
            throw TestFailure(message: "inference fixture missing/unreadable", file: #file, line: #line)
        }

        let detector: GLiNERDetector
        do {
            detector = try awaitSync { try await GLiNERDetector() }
        } catch GLiNERRuntime.RuntimeError.modelBundleMissing {
            return  // bundle is gitignored + regenerated locally.
        }

        let entities = try detector.detect(text: text, labels: labels, threshold: threshold)

        try expectEqual(entities.count, expected.count)
        for (got, want) in zip(entities, expected) {
            try expectEqual(got.start, want["start"] as? Int ?? -1)
            try expectEqual(got.end, want["end"] as? Int ?? -1)
            try expectEqual(got.text, want["text"] as? String ?? "")
            try expectEqual(got.label, want["label"] as? String ?? "")
            let wantScore = want["score"] as? Double ?? -1
            try expect(abs(got.score - wantScore) < 1e-4,
                       "score \(got.score) vs \(wantScore) for \(got.text)")
        }
    }

    s.test("detects entities across windows in a scene longer than the word limit") {
        let detector: GLiNERDetector
        do {
            detector = try awaitSync { try await GLiNERDetector() }
        } catch GLiNERRuntime.RuntimeError.modelBundleMissing {
            return  // bundle is gitignored + regenerated locally.
        }

        // 60 repetitions of the 8-word fixture sentence → 480 words,
        // well past the 300-word window cap → multiple windows. The
        // single-window path can't process this much text at all.
        let sentence = "Marek drew the dagger in the cathedral. "
        let repetitions = 60
        let longText = String(repeating: sentence, count: repetitions)

        let entities = try detector.detect(
            text: longText,
            labels: ["character", "place", "object"]
        )

        try expect(!entities.isEmpty, "no entities detected in the long scene")
        // Entities surface from the tail of the text — proof a later
        // window ran, not just the first 300 words.
        let maxStart = entities.map(\.start).max() ?? 0
        try expect(maxStart > GLiNERDetector.maxWindowWords * 5,
                   "max entity start \(maxStart) — later windows produced nothing")
        // Offsets stay absolute across windows — each entity's char
        // span slices back to exactly its reported text.
        let scalars = Array(longText.unicodeScalars)
        for e in entities {
            try expect(e.start >= 0 && e.end <= scalars.count && e.start < e.end,
                       "out-of-range span \(e.start)..<\(e.end)")
            let slice = String(String.UnicodeScalarView(scalars[e.start..<e.end]))
            try expectEqual(slice, e.text)
        }
    }

    return s
}
