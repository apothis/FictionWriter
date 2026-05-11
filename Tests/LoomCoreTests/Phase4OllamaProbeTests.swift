import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 1 — Ollama-kind profiles need a probe that
/// speaks Ollama's wire shape, not KoboldCpp's. `GET /api/tags`
/// returns the loaded models list; `OllamaProbe` parses it into the
/// same `ServerCapabilities` shape so the existing `AutoProbe.applyResult`
/// + capabilities-caching machinery keeps working unchanged.
///
/// modelName is the first loaded model's name (typically the only
/// one when the user runs `ollama pull <name>`). version + maxContext
/// are nil — Ollama's /api/version is a separate endpoint and the
/// model-context limit isn't reported by /api/tags. Phase 4.x can
/// extend if needed.
func phase4OllamaProbeTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaProbe")

    s.test("parseTagsResponse extracts the first model name from a real Ollama /api/tags payload") {
        // Verbatim shape from the live extractor server 2026-05-11.
        let json = """
        {
          "models": [
            {
              "name": "gemma4_2b:latest",
              "model": "gemma4_2b:latest",
              "size": 3450278234,
              "digest": "b1b0e9a3"
            },
            {
              "name": "gemma4_4b:latest",
              "model": "gemma4_4b:latest",
              "size": 5335286138,
              "digest": "d0524b8b"
            }
          ]
        }
        """
        let caps = try expectNotNil(OllamaProbe.parseTagsResponse(from: Data(json.utf8)))
        try expectEqual(caps.modelName, "gemma4_2b:latest")
        try expectNil(caps.version)
        try expectNil(caps.trueMaxContext)
    }

    s.test("parseTagsResponse returns nil when the models array is empty") {
        let json = """
        { "models": [] }
        """
        try expectNil(OllamaProbe.parseTagsResponse(from: Data(json.utf8)))
    }

    s.test("parseTagsResponse returns nil on unexpected shape") {
        try expectNil(OllamaProbe.parseTagsResponse(from: Data("not json".utf8)))
    }

    return s
}
