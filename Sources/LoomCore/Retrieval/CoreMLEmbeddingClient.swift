import Foundation
import CoreML
import Tokenizers

/// Phase 8.c — native macOS `EmbeddingClient` that runs the Wegmann
/// CoreML bundle (`StyleEmbedding/StyleEmbedding.mlpackage`) directly
/// via Apple's `MLModel` framework. Replaces the Phase 5
/// `PythonEmbeddingClient` for users who don't want a 3GB Python
/// venv sitting alongside the app.
///
/// Cosine-equivalent to the Python sentence-transformers path within
/// 1e-4 (verified by `Tools/CoreMLProbe/probe_wegmann_coreml.py`;
/// min 0.999993, max 0.999998). Existing `.index` sidecars produced
/// by the Python client remain valid — query-time cosine ranking is
/// preserved across the swap, no re-ingest needed.
///
/// Architecture:
/// - `StyleEmbedding/` resource bundle carries the `.mlpackage` and
///   the HuggingFace fast-tokenizer files (`tokenizer.json`,
///   `tokenizer_config.json`, …).
/// - First `embed(_:)` call lazy-loads both the tokenizer (via
///   `swift-transformers` `AutoTokenizer.from(modelFolder:)`) and
///   the CoreML model. A `DispatchSemaphore` bridges the async
///   tokenizer load to the synchronous `EmbeddingClient.embed`
///   contract — same shape `PythonEmbeddingClient` uses to bridge
///   its async subprocess spawn.
/// - Per-call: tokenize → pad/truncate to 128 tokens → `MLModel.
///   prediction(from:)` → return as `EmbeddingVector`. The mlpackage
///   bakes mean-pool + L2-norm into the graph; the Swift side just
///   reads the 768-vector output.
///
/// CLT-compatible at runtime (no Xcode required). `MLModel` is a
/// system framework; `xcrun coremlcompiler` ships with CLT.
public final class CoreMLEmbeddingClient: EmbeddingClient {
    /// Phase 8.c — the canonical model-id string written into the
    /// chunk-sidecar `dModel.id` field at ingest time and compared
    /// at retrieval/UI time to detect stale fingerprints. Surfaced
    /// as a static so callers (Bible Workspace snapshot builder)
    /// don't have to instantiate the client just to read its
    /// modelId. Must stay in sync with the `init` default below.
    public static let expectedModelId: String = "AnnaWegmann/Style-Embedding (CoreML)"

    public let modelId: String
    public let dim: Int
    /// Max sequence length the bundled mlpackage was traced with.
    /// Inputs longer than this are truncated to the first
    /// `maxSequenceLength - 2` tokens then re-wrapped with BOS/EOS
    /// (RoBERTa's `<s>` / `</s>`) before padding.
    public let maxSequenceLength: Int

    private let lock = NSLock()
    private let bundleURL: URL
    /// RoBERTa pad token id. The fast-tokenizer puts it in
    /// `tokenizer.json` and `<pad>` resolves to id 1 for
    /// `AnnaWegmann/Style-Embedding`; we read it from the loaded
    /// tokenizer at startup rather than hard-coding.
    private var padTokenId: Int = 1
    private var loaded: Loaded?

    private struct Loaded {
        let tokenizer: Tokenizer
        let model: MLModel
    }

    public init(
        bundleURL: URL,
        modelId: String = "AnnaWegmann/Style-Embedding (CoreML)",
        dim: Int = 768,
        maxSequenceLength: Int = 128
    ) {
        self.bundleURL = bundleURL
        self.modelId = modelId
        self.dim = dim
        self.maxSequenceLength = maxSequenceLength
    }

    /// Resolve the production bundle URL from `Bundle.module`. The
    /// `Resources/StyleEmbedding` directory was declared as a `.copy`
    /// resource on the `LoomCore` target; SPM exposes it under
    /// `Bundle.module.url(forResource: "StyleEmbedding", withExtension: nil)`.
    public static func defaultBundleURL() -> URL? {
        return Bundle.module.url(forResource: "StyleEmbedding", withExtension: nil)
    }

    public func embed(_ text: String) -> EmbeddingVector? {
        lock.lock()
        defer { lock.unlock() }

        let loaded: Loaded
        do {
            loaded = try ensureLoadedLocked()
        } catch {
            DebugLog.shared.write("[coreml-embed] load failed: \(error)")
            return nil
        }

        // Tokenize. `addSpecialTokens: true` triggers RoBERTa's
        // RobertaProcessing postprocessor (wraps the body in
        // `<s> ... </s>`), matching the Python tokenizer.
        var ids = loaded.tokenizer.encode(text: text, addSpecialTokens: true)
        if ids.count > maxSequenceLength {
            // Drop overflow + re-attach EOS so the sequence still
            // ends on </s>. Conservative truncation matches HF's
            // `truncation=True, max_length=N`.
            let eos = ids.last ?? 2
            ids = Array(ids.prefix(maxSequenceLength - 1)) + [eos]
        }
        let attentionMask: [Int32] =
            Array(repeating: 1, count: ids.count) +
            Array(repeating: 0, count: maxSequenceLength - ids.count)
        let paddedIds: [Int32] =
            ids.map(Int32.init) +
            Array(repeating: Int32(padTokenId), count: maxSequenceLength - ids.count)

        guard
            let inputIdsArray = try? MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32),
            let maskArray = try? MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        else {
            DebugLog.shared.write("[coreml-embed] failed to allocate MLMultiArray")
            return nil
        }
        for i in 0..<maxSequenceLength {
            inputIdsArray[i] = NSNumber(value: paddedIds[i])
            maskArray[i] = NSNumber(value: attentionMask[i])
        }

        let features: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ]
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: features),
              let prediction = try? loaded.model.prediction(from: provider) else {
            DebugLog.shared.write("[coreml-embed] prediction failed")
            return nil
        }

        // Pull the first output feature (named "embedding" in the
        // build script, but we don't rely on the name).
        guard let outputName = prediction.featureNames.first,
              let value = prediction.featureValue(for: outputName),
              let vec = value.multiArrayValue else {
            DebugLog.shared.write("[coreml-embed] missing output array")
            return nil
        }

        var values = [Float](repeating: 0, count: dim)
        for i in 0..<min(dim, vec.count) {
            values[i] = vec[i].floatValue
        }
        return EmbeddingVector(values: values)
    }

    private func ensureLoadedLocked() throws -> Loaded {
        if let loaded = self.loaded { return loaded }

        let pkgURL = bundleURL.appendingPathComponent("StyleEmbedding.mlpackage")
        // CoreML expects a compiled `.mlmodelc` at runtime. SPM
        // copies the `.mlpackage` as-is; `MLModel.compileModel(at:)`
        // produces an `.mlmodelc` on-the-fly. First-launch cost is
        // ~hundreds of ms; cached by macOS thereafter.
        let compiled: URL
        if pkgURL.pathExtension == "mlmodelc" {
            compiled = pkgURL
        } else {
            compiled = try MLModel.compileModel(at: pkgURL)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: compiled, configuration: config)

        // Block on the async tokenizer load. Loading from a local
        // folder never hits the network; ~50ms cost.
        let tokenizer = try blockOnAsync {
            try await AutoTokenizer.from(modelFolder: self.bundleURL)
        }
        // Resolve the RoBERTa pad token id from the loaded tokenizer
        // rather than hard-coding 1. `<pad>` is the canonical literal
        // in tokenizer.json.
        if let padId = tokenizer.convertTokenToId("<pad>") {
            self.padTokenId = padId
        }

        let loaded = Loaded(tokenizer: tokenizer, model: model)
        self.loaded = loaded
        DebugLog.shared.write("[coreml-embed] loaded mlpackage + tokenizer from \(bundleURL.path)")
        return loaded
    }

    /// Synchronous wrapper around an async throwing closure. The
    /// caller already holds the lock so re-entrancy from the same
    /// thread is impossible.
    private func blockOnAsync<T>(_ body: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task.detached {
            do {
                let value = try await body()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        switch result! {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}
