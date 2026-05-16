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

    return s
}
