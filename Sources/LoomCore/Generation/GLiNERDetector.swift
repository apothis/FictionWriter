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
    /// probability exceeds this. Lowered from GLiNER's Python default
    /// of 0.5: GLiNER scores a name differently per mention, and real
    /// character names land just under 0.5 on some prose — "Della"
    /// scored 0.492 on both mentions of a live scene (§15.27), missing
    /// the cutoff by 0.008 while pronoun noise sat far below (~0.31),
    /// leaving a clean gap to drop into.
    public static let defaultThreshold = 0.45

    /// Max words per inference window. GLiNER's `max_len` is 384 words;
    /// 300 leaves headroom for the label prompt and subword expansion.
    /// Longer scenes are windowed at sentence boundaries.
    public static let maxWindowWords = 300

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

        // Long scenes exceed GLiNER's max_len — window at sentence
        // boundaries and concatenate. Entities never cross a sentence
        // edge, so per-window results need no boundary dedup; char
        // offsets stay absolute because each Word keeps its source span.
        var entities: [GLiNEREntity] = []
        for window in GLiNERInputs.wordWindows(words: words, maxWords: Self.maxWindowWords) {
            entities += try detectWindow(
                windowWords: window,
                labels: labels,
                sourceText: text,
                threshold: threshold
            )
        }
        return entities
    }

    /// Run inference over one word-window and decode its entities.
    private func detectWindow(
        windowWords: [GLiNERInputs.Word],
        labels: [String],
        sourceText: String,
        threshold: Double
    ) throws -> [GLiNEREntity] {
        let numWords = windowWords.count
        guard numWords > 0 else { return [] }
        let inputs = tokenizer.buildInputs(words: windowWords.map(\.text), labels: labels)
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
            words: windowWords,
            sourceText: sourceText,
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
