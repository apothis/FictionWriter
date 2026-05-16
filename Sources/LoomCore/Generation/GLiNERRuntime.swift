import Foundation
import OnnxRuntimeBindings

/// GLiNER native entity detector — phase 2: ONNX Runtime is now linked
/// into LoomCore.
///
/// GLiNER is a small bidirectional NER encoder exported to ONNX by
/// `Tools/GLiNERProbe/export_gliner_onnx.py`. It replaces the
/// generative-LLM entity detector (which derails on explicit prose)
/// with a deterministic, refusal-proof tagger.
///
/// This type is the thin entry point. The full inference path — the
/// DeBERTa-v3 tokenizer, span enumeration, and sigmoid decode — lands
/// in later phases; for now it owns the ONNX Runtime environment and
/// can open an inference session against the exported model bundle.
public enum GLiNERRuntime {
    /// Subdirectory of `LoomCore`'s resource bundle holding the
    /// exported ONNX model + tokenizer assets.
    public static let bundleSubdirectory = "GLiNER"
    public static let modelFileName = "model_quantized.onnx"

    public enum RuntimeError: Error {
        /// The exported model bundle isn't present in the app bundle —
        /// run `Tools/GLiNERProbe/export_gliner_onnx.py`.
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

    /// Open an ONNX Runtime inference session against the exported
    /// GLiNER model. Phases 3+ add tokenisation + span decode on top.
    public static func makeSession(env: ORTEnv) throws -> ORTSession {
        let options = try ORTSessionOptions()
        return try ORTSession(
            env: env,
            modelPath: try modelURL().path,
            sessionOptions: options
        )
    }
}
