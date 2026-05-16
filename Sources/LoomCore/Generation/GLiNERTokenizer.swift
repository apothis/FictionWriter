import Foundation
import Tokenizers

/// GLiNER native entity detector — phase 3: the tokenizer.
///
/// GLiNER's ONNX graph expects DeBERTa-v3 SentencePiece token ids. The
/// exported bundle's `tokenizer_config.json` declares the tokenizer
/// class as `XLMRobertaTokenizer` (rewritten by
/// `Tools/GLiNERProbe/export_gliner_onnx.py`) so swift-transformers
/// loads it as its generic Unigram tokenizer — all normalizer /
/// pre-tokenizer / decoder behaviour is driven by `tokenizer.json`
/// regardless of the class name.
///
/// Byte-for-byte parity with the Python tokenizer the ONNX model was
/// trained against is pinned by `GLiNERTokenizerTests` against a
/// fixture (`Tools/GLiNERProbe/dump_tokenizer_fixture.py`).
public final class GLiNERTokenizer {
    private let tokenizer: any Tokenizer

    /// Load the tokenizer from the exported GLiNER resource bundle.
    /// Throws `GLiNERRuntime.RuntimeError.modelBundleMissing` when the
    /// bundle hasn't been exported.
    public init() async throws {
        let folder = try GLiNERRuntime.bundleDirectoryURL()
        tokenizer = try await AutoTokenizer.from(modelFolder: folder)
    }

    /// Encode `text` to DeBERTa-v3 token ids, including the [CLS] /
    /// [SEP] special tokens the model's input sequence expects.
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text)
    }
}
