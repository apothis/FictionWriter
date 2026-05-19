import Foundation
@testable import LoomCore

/// Continuity Audit NLI gate — runtime linkage tests. Confirms ONNX
/// Runtime is linked and can open a session against the exported NLI
/// model. Tokenisation + decode land in `NLICrossEncoder`.
func nliRuntimeTests() -> TestSuite {
    let s = TestSuite("NLIRuntime")

    s.test("ONNX Runtime environment initialises (linkage smoke)") {
        _ = try NLIRuntime.makeEnvironment()
    }

    s.test("exported NLI model loads into an ONNX Runtime session when present") {
        let env = try NLIRuntime.makeEnvironment()
        do {
            _ = try NLIRuntime.makeSession(env: env)
        } catch NLIRuntime.RuntimeError.modelBundleMissing {
            // The ONNX bundle is gitignored and regenerated locally;
            // when it hasn't been exported, ONNX Runtime linkage is
            // still proven by the environment test above.
        }
    }

    return s
}
