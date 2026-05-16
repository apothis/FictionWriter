import Foundation
@testable import LoomCore

/// GLiNER native entity detector — phase 4a input-construction tests.
/// Verified against the ground-truth fixture dumped from the Python
/// GLiNER ONNX path (Tools/GLiNERProbe agent spec).
func glinerInputsTests() -> TestSuite {
    let s = TestSuite("GLiNERInputs")

    // The fixture text: "Marek drew the dagger in the cathedral."
    // → 8 words: Marek drew the dagger in the cathedral .

    s.test("splitWords splits on whitespace, punctuation as its own word") {
        let words = GLiNERInputs.splitWords("Marek drew the dagger in the cathedral.")
        try expectEqual(words.map(\.text),
                        ["Marek", "drew", "the", "dagger", "in", "the", "cathedral", "."])
        // Char offsets match Python re.finditer (the fixture's
        // decoded entity offsets: Marek 0–5, dagger 15–21, cathedral 29–38).
        try expectEqual(words[0].start, 0)
        try expectEqual(words[0].end, 5)
        try expectEqual(words[3].start, 15)
        try expectEqual(words[3].end, 21)
        try expectEqual(words[6].start, 29)
        try expectEqual(words[6].end, 38)
    }

    s.test("splitWords keeps internal hyphens and underscores within a word") {
        let words = GLiNERInputs.splitWords("ex-girlfriend snake_case word")
        try expectEqual(words.map(\.text), ["ex-girlfriend", "snake_case", "word"])
    }

    s.test("splitWords on empty / whitespace-only text → no words") {
        try expectEqual(GLiNERInputs.splitWords("").count, 0)
        try expectEqual(GLiNERInputs.splitWords("   \n  ").count, 0)
    }

    s.test("spanIndices enumerates start × width pairs matching the fixture") {
        let spans = GLiNERInputs.spanIndices(wordCount: 8)
        try expectEqual(spans.count, 8 * 12)
        // First word, widths 0…11.
        try expectEqual(spans[0], [0, 0])
        try expectEqual(spans[11], [0, 11])
        // Second word starts at index 12.
        try expectEqual(spans[12], [1, 1])
        try expectEqual(spans[13], [1, 2])
        // Last word.
        try expectEqual(spans[84], [7, 7])
        try expectEqual(spans[95], [7, 18])
    }

    s.test("spanMask flags a span valid iff its end word is in range") {
        let mask = GLiNERInputs.spanMask(wordCount: 8)
        try expectEqual(mask.count, 96)
        // 36 valid spans for an 8-word text (the fixture's count).
        try expectEqual(mask.filter { $0 }.count, 36)
        // word 0: widths 0…7 valid (end ≤ 7), 8…11 invalid.
        try expectEqual(Array(mask[0..<12]),
                        [true, true, true, true, true, true, true, true,
                         false, false, false, false])
        // word 7: only width 0 valid.
        try expectEqual(mask[84], true)
        try expectEqual(mask[85], false)
    }

    s.test("assembleSequence lays out [CLS] <<ENT>> labels <<SEP>> words [SEP] like the fixture") {
        // Subword ids taken from the fixture (each label/word is one
        // subword for this sentence): character→1470, place→470,
        // object→2713; Marek→66879 drew→6576 the→262 dagger→37276
        // in→267 the→262 cathedral→18410 .→323.
        let labels = [[1470], [470], [2713]]
        let words = [[66879], [6576], [262], [37276], [267], [262], [18410], [323]]
        let inputs = GLiNERInputs.assembleSequence(labelSubwords: labels, wordSubwords: words)
        try expectEqual(inputs.inputIDs,
                        [1, 128002, 1470, 128002, 470, 128002, 2713, 128003,
                         66879, 6576, 262, 37276, 267, 262, 18410, 323, 2])
        try expectEqual(inputs.attentionMask, Array(repeating: 1, count: 17))
        try expectEqual(inputs.wordsMask,
                        [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0])
        try expectEqual(inputs.textLength, 8)
    }

    s.test("assembleSequence marks only the first subword of a multi-subword word") {
        // Word 0 has two subwords, word 1 has one.
        let inputs = GLiNERInputs.assembleSequence(
            labelSubwords: [[100]],
            wordSubwords: [[200, 201], [202]]
        )
        try expectEqual(inputs.inputIDs, [1, 128002, 100, 128003, 200, 201, 202, 2])
        // [CLS] <<ENT>> label <<SEP>> → 0; word0 first→1, cont→0; word1→2; [SEP]→0.
        try expectEqual(inputs.wordsMask, [0, 0, 0, 0, 1, 0, 2, 0])
        try expectEqual(inputs.textLength, 2)
    }

    s.test("input builders match the fixture's span tensors exactly") {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gliner_inference_fixture.json")
        guard let data = try? Data(contentsOf: fixtureURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inputs = root["input_tensors"] as? [String: Any]
        else {
            throw TestFailure(message: "fixture missing/unreadable", file: #file, line: #line)
        }
        // span_idx: [[ [s,e], … ]] → flatten the batch dim.
        let spanIdxRaw = (inputs["span_idx"] as? [String: Any])?["values"] as? [[[Int]]]
        let expectedSpans = try expectNotNil(spanIdxRaw).first!
        try expectEqual(GLiNERInputs.spanIndices(wordCount: 8), expectedSpans)

        let spanMaskRaw = (inputs["span_mask"] as? [String: Any])?["values"] as? [[Bool]]
        let expectedMask = try expectNotNil(spanMaskRaw).first!
        try expectEqual(GLiNERInputs.spanMask(wordCount: 8), expectedMask)
    }

    s.test("wordWindows returns the whole text as one window when under the limit") {
        let words = GLiNERInputs.splitWords("Marek drew the dagger.")
        let windows = GLiNERInputs.wordWindows(words: words, maxWords: 300)
        try expectEqual(windows.count, 1)
        try expectEqual(windows[0].count, words.count)
    }

    s.test("wordWindows splits at sentence boundaries, each window under the limit") {
        // 6 three-word sentences ("a b c." = 4 words each → 24 words).
        let prose = Array(repeating: "a b c.", count: 6).joined(separator: " ")
        let words = GLiNERInputs.splitWords(prose)
        let windows = GLiNERInputs.wordWindows(words: words, maxWords: 9)
        // 9-word cap → 2 sentences (8 words) per window → 3 windows.
        try expectEqual(windows.count, 3)
        for w in windows {
            try expect(w.count <= 9, "window of \(w.count) exceeds cap")
        }
        // No word is dropped or duplicated.
        try expectEqual(windows.reduce(0) { $0 + $1.count }, words.count)
        // Every window ends on a sentence terminator.
        for w in windows {
            try expectEqual(w.last?.text, ".")
        }
    }

    s.test("wordWindows hard-splits a single sentence longer than the limit") {
        // One 20-word sentence, cap 8.
        let prose = Array(repeating: "w", count: 19).joined(separator: " ") + " end."
        let words = GLiNERInputs.splitWords(prose)  // 21 words incl. "."
        let windows = GLiNERInputs.wordWindows(words: words, maxWords: 8)
        try expect(windows.count >= 3, "expected hard-split into 3+ windows")
        for w in windows {
            try expect(w.count <= 8, "window of \(w.count) exceeds cap")
        }
        try expectEqual(windows.reduce(0) { $0 + $1.count }, words.count)
    }

    return s
}
