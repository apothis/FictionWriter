import Foundation
import OnnxRuntimeBindings

/// Continuity Audit NLI proposition gate — the ONNX Runtime entry point
/// (`LOOM_CONTINUITY_AUDIT.md` §25, Part A).
///
/// The audit pairs claims by embedding cosine, which scores *topic* not
/// *proposition* (§24). A DeBERTa-v3 NLI cross-encoder scores a claim
/// pair jointly and labels it `contradiction` / `entailment` /
/// `neutral`; the gate drops `neutral` pairs — topical look-alikes —
/// before the LLM adjudicator sees them.
///
/// The model is exported to ONNX by `Tools/NLIProbe/export_nli_onnx.py`
/// and run via ONNX Runtime — the same runtime already linked for
/// GLiNER. This type owns the runtime environment and opens an
/// inference session; tokenisation + softmax decode sit in
/// `NLICrossEncoder`.
public enum NLIRuntime {
    /// Subdirectory of `LoomCore`'s resource bundle holding the
    /// exported ONNX model + tokenizer assets.
    public static let bundleSubdirectory = "NLI"
    /// FP32 — INT8 quantization flips this model's verdicts (see
    /// `Tools/NLIProbe/export_nli_onnx.py`).
    public static let modelFileName = "model.onnx"

    public enum RuntimeError: Error {
        /// The exported model bundle isn't present in the app bundle —
        /// run `Tools/NLIProbe/export_nli_onnx.py`.
        case modelBundleMissing
    }

    /// Create an ONNX Runtime environment. Throws if the linked
    /// runtime fails to initialise.
    public static func makeEnvironment() throws -> ORTEnv {
        try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
    }

    /// Resolve the exported model file inside `LoomCore`'s resource
    /// bundle. Throws `modelBundleMissing` when the export hasn't been
    /// run (the bundle is gitignored + regenerated locally).
    public static func modelURL() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: modelFileName,
            withExtension: nil,
            subdirectory: bundleSubdirectory
        ) else {
            throw RuntimeError.modelBundleMissing
        }
        return url
    }

    /// Resolve the exported NLI bundle *directory* — the folder holding
    /// the ONNX model and the tokenizer assets.
    public static func bundleDirectoryURL() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: bundleSubdirectory,
            withExtension: nil
        ) else {
            throw RuntimeError.modelBundleMissing
        }
        return url
    }

    /// Open an ONNX Runtime inference session against the exported NLI
    /// model. `NLICrossEncoder` adds tokenisation + decode on top.
    public static func makeSession(env: ORTEnv) throws -> ORTSession {
        let options = try ORTSessionOptions()
        return try ORTSession(
            env: env,
            modelPath: try modelURL().path,
            sessionOptions: options
        )
    }
}
