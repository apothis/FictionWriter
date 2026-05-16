import Foundation

/// A detected entity span. Char offsets are Unicode-scalar indices into
/// the source text, matching the offsets GLiNER's Python decode reports.
public struct GLiNEREntity: Equatable {
    public let start: Int
    public let end: Int
    public let text: String
    public let label: String
    public let score: Double

    public init(start: Int, end: Int, text: String, label: String, score: Double) {
        self.start = start
        self.end = end
        self.text = text
        self.label = label
        self.score = score
    }
}

/// GLiNER native entity detector — phase 4c: span-logit decode.
///
/// Turns the model's raw `logits[1, numWords, maxSpanWidth, numClasses]`
/// into entities (`gliner/decoding/decoder.py`): sigmoid → threshold →
/// validity-filter → greedy non-overlapping selection → word-span →
/// char-offset mapping.
public enum GLiNERDecoder {
    /// Decode flattened span logits into non-overlapping entities.
    ///
    /// - Parameters:
    ///   - logits: row-major `[numWords][maxSpanWidth][numClasses]`.
    ///   - numWords: word count (the model's `text_lengths`).
    ///   - labels: entity-type names, in the order they were prompted —
    ///     a logit's class index indexes into this.
    ///   - words: the split words, carrying their char spans.
    ///   - sourceText: original prose, for slicing entity text.
    ///   - threshold: a span is kept iff `sigmoid(logit) > threshold`
    ///     (strict — matching GLiNER's `torch.where(probs > t)`).
    public static func decode(
        logits: [Float],
        numWords: Int,
        labels: [String],
        words: [GLiNERInputs.Word],
        sourceText: String,
        threshold: Double
    ) -> [GLiNEREntity] {
        guard numWords > 0, !labels.isEmpty, words.count >= numWords else { return [] }
        let numClasses = labels.count
        let maxWidth = GLiNERInputs.maxSpanWidth

        struct Candidate {
            let startWord: Int
            let endWord: Int
            let cls: Int
            let score: Double
        }
        var candidates: [Candidate] = []

        for s in 0..<numWords {
            for k in 0..<maxWidth {
                // Validity filter: the end word must be within the
                // text. The quantized model emits a constant garbage
                // logit on out-of-range span rows — keeping them would
                // surface phantom entities.
                guard s + k + 1 <= numWords else { continue }
                for c in 0..<numClasses {
                    let idx = ((s * maxWidth) + k) * numClasses + c
                    guard idx < logits.count else { continue }
                    let prob = 1.0 / (1.0 + exp(-Double(logits[idx])))
                    if prob > threshold {
                        candidates.append(Candidate(
                            startWord: s, endWord: s + k, cls: c, score: prob
                        ))
                    }
                }
            }
        }

        // Greedy flat-NER selection: highest score first, drop any span
        // overlapping an already-kept one (word ranges intersect).
        candidates.sort { $0.score > $1.score }
        var selected: [Candidate] = []
        for cand in candidates {
            let overlaps = selected.contains { kept in
                !(cand.startWord > kept.endWord || kept.startWord > cand.endWord)
            }
            if !overlaps { selected.append(cand) }
        }
        selected.sort { $0.startWord < $1.startWord }

        let scalars = Array(sourceText.unicodeScalars)
        return selected.map { cand in
            let charStart = words[cand.startWord].start
            let charEnd = words[cand.endWord].end
            let text = String(String.UnicodeScalarView(scalars[charStart..<charEnd]))
            return GLiNEREntity(
                start: charStart,
                end: charEnd,
                text: text,
                label: labels[cand.cls],
                score: cand.score
            )
        }
    }
}
