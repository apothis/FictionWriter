import Foundation
@testable import LoomCore

/// GLiNER native entity detector — phase 2 linkage tests. Confirms
/// ONNX Runtime is linked into LoomCore and can open a session against
/// the exported GLiNER model. The tokenizer + span-decode inference
/// path lands in later phases.
func glinerRuntimeTests() -> TestSuite {
    let s = TestSuite("GLiNERRuntime")

    s.test("ONNX Runtime environment initialises (linkage smoke)") {
        _ = try GLiNERRuntime.makeEnvironment()
    }

    s.test("exported GLiNER model loads into an ONNX Runtime session when present") {
        let env = try GLiNERRuntime.makeEnvironment()
        do {
            _ = try GLiNERRuntime.makeSession(env: env)
        } catch GLiNERRuntime.RuntimeError.modelBundleMissing {
            // The ONNX bundle is gitignored and regenerated locally;
            // when it hasn't been exported, ONNX Runtime linkage is
            // still proven by the environment test above.
        }
    }

    return s
}
