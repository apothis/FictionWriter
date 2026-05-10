import Foundation
@testable import LoomCore

/// Sub-step 1.c — pure parse-helper tests for ServerProbe. The probe
/// itself does network work that we don't unit-test (smoke covers that);
/// the JSON-shape parsing is pure and testable. Mirrors RPClient's
/// `serverProbeParseTests` posture.
func phase1ServerProbeParseTests() -> TestSuite {
    let s = TestSuite("Phase1ServerProbeParse")

    s.test("parseModelName extracts the result field") {
        let json = #"{"result":"koboldcpp/llama-cpp/Qwen2.5-72B-Instruct.gguf"}"#
        let name = ServerProbe.parseModelName(from: Data(json.utf8))
        try expectEqual(name, "koboldcpp/llama-cpp/Qwen2.5-72B-Instruct.gguf")
    }

    s.test("parseModelName returns nil on malformed JSON") {
        let name = ServerProbe.parseModelName(from: Data("not-json".utf8))
        try expectNil(name)
    }

    s.test("parseVersion accepts both 'result' and 'version' keys") {
        let a = ServerProbe.parseVersion(from: Data(#"{"result":"1.95.0"}"#.utf8))
        try expectEqual(a, "1.95.0")
        let b = ServerProbe.parseVersion(from: Data(#"{"version":"1.94.1"}"#.utf8))
        try expectEqual(b, "1.94.1")
    }

    s.test("parseTrueMaxContext extracts integer value") {
        let n = ServerProbe.parseTrueMaxContext(from: Data(#"{"value":32768}"#.utf8))
        try expectEqual(n, 32768)
    }

    s.test("parseTrueMaxContext returns nil when value missing") {
        let n = ServerProbe.parseTrueMaxContext(from: Data("{}".utf8))
        try expectNil(n)
    }

    return s
}
