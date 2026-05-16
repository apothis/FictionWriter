import Foundation
import OnnxRuntimeBindings

/// GLiNER native entity detector — phase 4c: the full inference path.
///
/// Composes the pieces built in phases 2–4b — the ONNX session, the
/// DeBERTa-v3 tokenizer, input construction — and the phase-4c decode
/// into a single `detect` call: prose + label set → entity spans.
///
/// GLiNER is a bidirectional NER encoder; unlike the generative Stage
/// A2 it replaces, it is deterministic and cannot refuse or derail on
/// explicit prose.
public final class GLiNERDetector {
    private let env: ORTEnv
    private let session: ORTSession
    private let tokenizer: GLiNERTokenizer

    /// Default detection threshold — a span is kept iff its sigmoid
    /// probability exceeds this. Matches GLiNER's Python default.
    public static let defaultThreshold = 0.5

    /// Load the detector from the exported GLiNER resource bundle.
    /// Throws `GLiNERRuntime.RuntimeError.modelBundleMissing` when the
    /// bundle hasn't been exported.
    public init() async throws {
        env = try GLiNERRuntime.makeEnvironment()
        session = try GLiNERRuntime.makeSession(env: env)
        tokenizer = try await GLiNERTokenizer()
    }

    /// Detect entities of the given `labels` in `text`.
    ///
    /// `labels` are free-text type names (e.g. `character`, `place`,
    /// `object`); GLiNER scores every candidate span against each.
    public func detect(
        text: String,
        labels: [String],
        threshold: Double = defaultThreshold
    ) throws -> [GLiNEREntity] {
        let words = GLiNERInputs.splitWords(text)
        guard !words.isEmpty, !labels.isEmpty else { return [] }

        let numWords = words.count
        let inputs = tokenizer.buildInputs(words: words.map(\.text), labels: labels)
        let seqLen = inputs.inputIDs.count
        let spans = GLiNERInputs.spanIndices(wordCount: numWords)
        let spanMask = GLiNERInputs.spanMask(wordCount: numWords)
        let numSpans = spans.count

        let feeds: [String: ORTValue] = [
            "input_ids": try int64Tensor(inputs.inputIDs, shape: [1, seqLen]),
            "attention_mask": try int64Tensor(inputs.attentionMask, shape: [1, seqLen]),
            "words_mask": try int64Tensor(inputs.wordsMask, shape: [1, seqLen]),
            "text_lengths": try int64Tensor([inputs.textLength], shape: [1, 1]),
            "span_idx": try int64Tensor(spans.flatMap { $0 }, shape: [1, numSpans, 2]),
            // span_mask was retyped bool → int64 by the export-time
            // graph surgery (a Cast node restores bool inside the graph).
            "span_mask": try int64Tensor(spanMask.map { $0 ? 1 : 0 }, shape: [1, numSpans]),
        ]

        let outputs = try session.run(
            withInputs: feeds,
            outputNames: ["logits"],
            runOptions: nil
        )
        guard let logitsValue = outputs["logits"] else {
            throw GLiNERRuntime.RuntimeError.modelBundleMissing
        }
        let logits = try floats(from: logitsValue)

        return GLiNERDecoder.decode(
            logits: logits,
            numWords: numWords,
            labels: labels,
            words: words,
            sourceText: text,
            threshold: threshold
        )
    }

    /// Wrap an `[Int]` as an int64 ORT tensor of the given shape.
    private func int64Tensor(_ values: [Int], shape: [Int]) throws -> ORTValue {
        var ints = values.map { Int64($0) }
        let data = NSMutableData(
            bytes: &ints,
            length: ints.count * MemoryLayout<Int64>.stride
        )
        return try ORTValue(
            tensorData: data,
            elementType: .int64,
            shape: shape.map { NSNumber(value: $0) }
        )
    }

    /// Read a float32 ORT tensor's data into a Swift `[Float]`.
    private func floats(from value: ORTValue) throws -> [Float] {
        let data = try value.tensorData()
        let count = data.length / MemoryLayout<Float>.stride
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBytes { data.getBytes($0.baseAddress!, length: data.length) }
        return out
    }
}
