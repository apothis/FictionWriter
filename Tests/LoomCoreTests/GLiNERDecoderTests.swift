import Foundation
@testable import LoomCore

/// GLiNER native entity detector — phase 4c decode tests.
///
/// The decode turns the model's raw span logits into entities:
/// sigmoid → threshold → validity-filter → greedy non-overlapping
/// selection → word-span → char-offset mapping. Verified against the
/// ground-truth fixture dumped from the Python GLiNER ONNX path.
func glinerDecoderTests() -> TestSuite {
    let s = TestSuite("GLiNERDecoder")

    s.test("decodes the fixture logits into the expected entities") {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gliner_inference_fixture.json")
        guard let data = try? Data(contentsOf: fixtureURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["input_text"] as? String,
              let labels = root["labels"] as? [String],
              let threshold = root["threshold"] as? Double,
              let outputs = root["output_tensors"] as? [String: Any],
              let logitsObj = outputs["logits"] as? [String: Any],
              // [1][numWords][12][numClasses]
              let nested = logitsObj["values"] as? [[[[Double]]]]
        else {
            throw TestFailure(message: "inference fixture missing/unreadable", file: #file, line: #line)
        }

        let logits = nested[0].flatMap { $0.flatMap { $0.map { Float($0) } } }
        let words = GLiNERInputs.splitWords(text)

        let entities = GLiNERDecoder.decode(
            logits: logits,
            numWords: words.count,
            labels: labels,
            words: words,
            sourceText: text,
            threshold: threshold
        )

        try expectEqual(entities.count, 3)
        // Entities are returned sorted by start offset.
        try expectEqual(entities.map(\.text), ["Marek", "dagger", "cathedral"])
        try expectEqual(entities.map(\.label), ["character", "object", "place"])
        try expectEqual(entities.map { [$0.start, $0.end] },
                        [[0, 5], [15, 21], [29, 38]])
        try expect(abs(entities[0].score - 0.8788785338401794) < 1e-5,
                   "Marek score \(entities[0].score)")
        try expect(abs(entities[1].score - 0.6542973518371582) < 1e-5,
                   "dagger score \(entities[1].score)")
        try expect(abs(entities[2].score - 0.909193754196167) < 1e-5,
                   "cathedral score \(entities[2].score)")
    }

    s.test("validity filter discards spans whose end word is out of range") {
        // 2 words, 1 class. Every span row carries a high logit, but
        // only spans with start+width+1 <= numWords are real.
        let numWords = 2, classes = 1
        let logits = [Float](repeating: 5.0, count: numWords * 12 * classes)
        let words = [
            GLiNERInputs.Word(text: "Ana", start: 0, end: 3),
            GLiNERInputs.Word(text: "ran", start: 4, end: 7),
        ]
        let entities = GLiNERDecoder.decode(
            logits: logits,
            numWords: numWords,
            labels: ["x"],
            words: words,
            sourceText: "Ana ran",
            threshold: 0.5
        )
        // word0 width0 [0,0] and word1 width0 [1,1] overlap nothing
        // each other; word0 width1 [0,1] would overlap both. Greedy by
        // equal score keeps the first seen non-overlapping spans, but
        // the key assertion: no span reaches past word index 1.
        for e in entities {
            try expect(e.end <= 7, "span end \(e.end) past last word")
        }
    }

    return s
}
