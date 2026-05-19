import Foundation
import OnnxRuntimeBindings
import Tokenizers

/// Continuity Audit NLI proposition gate — the cross-encoder
/// (`LOOM_CONTINUITY_AUDIT.md` §25, Part A).
///
/// Wraps the exported DeBERTa-v3 NLI ONNX model: pair-tokenises two
/// claims, runs the model, softmax-decodes to one of
/// `{entailment, neutral, contradiction}`. The gate caller drops
/// `neutral` pairs (topical look-alikes) before LLM adjudication.
///
/// Pair tokenisation. DeBERTa-v3's single-text template is
/// `[CLS] X [SEP]`, and its pair template is `[CLS] A [SEP] B [SEP]`
/// (single SEP between, BERT-style). swift-transformers' Tokenizer has
/// no pair-encode API, but concatenating
/// `encode(A) + encode(B).dropFirst()` reproduces the pair template
/// exactly — dropping B's leading `[CLS]` leaves
/// `[CLS] A [SEP] | B [SEP]`. Byte-for-byte parity with Python's
/// pair tokenizer is pinned by `NLICrossEncoderTests` against
/// `Tools/NLIProbe/dump_tokenizer_fixture.py`.
public final class NLICrossEncoder {

    /// The three NLI verdicts the model emits.
    public enum Label: String, Equatable, CaseIterable {
        case entailment
        case neutral
        case contradiction
    }

    public struct Result: Equatable {
        public let label: Label
        public let probs: [Label: Float]
        public init(label: Label, probs: [Label: Float]) {
            self.label = label
            self.probs = probs
        }
    }

    public enum InferenceError: Error {
        /// The session ran but did not produce the expected `logits`
        /// output — exported bundle is malformed.
        case missingLogits
        /// The bundled `config.json` does not carry a usable id2label
        /// map — exported bundle is malformed.
        case malformedConfig
    }

    private let tokenizer: any Tokenizer
    private let session: ORTSession
    /// Index → verdict, read from the bundled `config.json`. The model
    /// emits logits in this order; the Swift side does not hard-code
    /// it, in case a future export changes the index assignment.
    private let labelOrder: [Label]

    public init(env: ORTEnv) async throws {
        let folder = try NLIRuntime.bundleDirectoryURL()
        self.tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        self.session = try NLIRuntime.makeSession(env: env)
        self.labelOrder = try Self.loadLabelOrder(in: folder)
    }

    /// Pair-tokenise `premise` and `hypothesis` into the model's
    /// `[CLS] premise [SEP] hypothesis [SEP]` input sequence.
    public func encodePair(
        premise: String, hypothesis: String
    ) -> (inputIDs: [Int], attentionMask: [Int]) {
        let encA = tokenizer.encode(text: premise)
        let encB = tokenizer.encode(text: hypothesis)
        // Single template = [CLS] X [SEP]; concat A + B.dropFirst()
        // produces [CLS] A [SEP] B [SEP], which is DeBERTa-v3's pair
        // template — verified against Python by NLICrossEncoderTests.
        let ids = encA + Array(encB.dropFirst())
        let mask = Array(repeating: 1, count: ids.count)
        return (ids, mask)
    }

    /// Score a claim pair. Returns the argmax label plus the full
    /// softmax distribution (callers may want the raw probabilities to
    /// log or threshold on).
    public func score(premise: String, hypothesis: String) throws -> Result {
        let (ids, mask) = encodePair(premise: premise, hypothesis: hypothesis)
        let seqLen = ids.count

        let feeds: [String: ORTValue] = [
            "input_ids": try Self.int64Tensor(ids, shape: [1, seqLen]),
            "attention_mask": try Self.int64Tensor(mask, shape: [1, seqLen]),
        ]
        let outputs = try session.run(
            withInputs: feeds, outputNames: ["logits"], runOptions: nil)
        guard let logitsValue = outputs["logits"] else {
            throw InferenceError.missingLogits
        }
        let logits = try Self.floats(from: logitsValue)
        let probs = Self.softmax(logits)

        var bestIdx = 0
        for i in 1..<probs.count where probs[i] > probs[bestIdx] { bestIdx = i }
        var dict: [Label: Float] = [:]
        for (i, p) in probs.enumerated() where i < labelOrder.count {
            dict[labelOrder[i]] = p
        }
        return Result(label: labelOrder[bestIdx], probs: dict)
    }

    // MARK: - Helpers

    private static func loadLabelOrder(in folder: URL) throws -> [Label] {
        let cfgURL = folder.appendingPathComponent("config.json")
        let data = try Data(contentsOf: cfgURL)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id2 = obj["id2label"] as? [String: String] else {
            throw InferenceError.malformedConfig
        }
        var out: [Label] = []
        for i in 0..<id2.count {
            guard let raw = id2[String(i)]?.lowercased(),
                  let lbl = Label(rawValue: raw) else {
                throw InferenceError.malformedConfig
            }
            out.append(lbl)
        }
        return out
    }

    private static func int64Tensor(_ values: [Int], shape: [Int]) throws -> ORTValue {
        var ints = values.map { Int64($0) }
        let data = NSMutableData(
            bytes: &ints, length: ints.count * MemoryLayout<Int64>.stride)
        return try ORTValue(
            tensorData: data,
            elementType: .int64,
            shape: shape.map { NSNumber(value: $0) }
        )
    }

    private static func floats(from value: ORTValue) throws -> [Float] {
        let data = try value.tensorData()
        let count = data.length / MemoryLayout<Float>.stride
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBytes { data.getBytes($0.baseAddress!, length: data.length) }
        return out
    }

    private static func softmax(_ logits: [Float]) -> [Float] {
        guard let m = logits.max() else { return [] }
        let exps = logits.map { Float(exp(Double($0 - m))) }
        let sum = exps.reduce(0, +)
        return sum > 0 ? exps.map { $0 / sum } : exps
    }
}

public extension NLICrossEncoder {

    /// Production hookup for `ContinuityAuditEngine.worldFactPairFilter`:
    /// returns a closure that scores a candidate pair and keeps it iff
    /// the NLI verdict is *not* `neutral`. A scoring failure falls open
    /// (the pair is kept and the LLM adjudicates as before) — the gate
    /// should never silently drop pairs because of an inference glitch.
    func worldFactFilter() -> (ContinuityAudit.Claim, ContinuityAudit.Claim) -> Bool {
        return { [weak self] earlier, later in
            guard let self = self else { return true }
            guard let r = try? self.score(premise: earlier.value, hypothesis: later.value)
            else { return true }
            return r.label != .neutral
        }
    }
}
