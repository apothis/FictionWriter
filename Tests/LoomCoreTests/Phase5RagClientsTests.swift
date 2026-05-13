import Foundation
@testable import LoomCore

/// Pure-data response parsers for the Phase 5 RAG spike's embedding
/// clients (LOOM_RAG_SPIKE.md §6 S3). The actual HTTP transport
/// lives in `Tools/RagSpike` and is exercised by the spike runner,
/// not by TestKit; what we pin here is the deserialisation contract
/// against canned JSON payloads from each backend.
func phase5RagClientsTests() -> TestSuite {
    let s = TestSuite("Phase5RagClients")

    // MARK: - Kobold (/v1/embeddings)

    s.test("Kobold response decodes a single embedding") {
        let json = """
        {
          "object": "list",
          "data": [
            {"object": "embedding", "index": 0, "embedding": [0.1, 0.2, -0.3]}
          ]
        }
        """.data(using: .utf8)!
        let vec = try expectNotNil(KoboldEmbeddingsResponse.decode(json))
        try expectEqual(vec.dim, 3)
        try expectEqual(vec.values, [0.1, 0.2, -0.3])
    }

    s.test("Kobold response decodes a 768-dim nomic vector") {
        // Realistic shape — payload truncated for readability but length
        // verified.
        let dim = 768
        let arr = (0..<dim).map { _ in "0.01" }.joined(separator: ", ")
        let json = """
        {"object":"list","data":[{"object":"embedding","index":0,"embedding":[\(arr)]}]}
        """.data(using: .utf8)!
        let vec = try expectNotNil(KoboldEmbeddingsResponse.decode(json))
        try expectEqual(vec.dim, 768)
    }

    s.test("Kobold response with empty data array returns nil (caller surfaces error)") {
        let json = """
        {"object": "list", "data": []}
        """.data(using: .utf8)!
        try expectNil(KoboldEmbeddingsResponse.decode(json))
    }

    s.test("Kobold response with malformed JSON returns nil") {
        let json = "not json at all".data(using: .utf8)!
        try expectNil(KoboldEmbeddingsResponse.decode(json))
    }

    // MARK: - Ollama (/api/embed)

    s.test("Ollama response decodes a single embedding from the embeddings array") {
        // /api/embed returns an array of embeddings (supports batched
        // input). The spike sends one input at a time and reads
        // embeddings[0].
        let json = """
        {
          "model": "mxbai-embed-large",
          "embeddings": [[0.5, -0.5, 0.25, -0.25]]
        }
        """.data(using: .utf8)!
        let vec = try expectNotNil(OllamaEmbedResponse.decode(json))
        try expectEqual(vec.dim, 4)
        try expectEqual(vec.values, [0.5, -0.5, 0.25, -0.25])
    }

    s.test("Ollama response decodes a 1024-dim mxbai vector") {
        let dim = 1024
        let arr = (0..<dim).map { _ in "0.001" }.joined(separator: ", ")
        let json = """
        {"model":"mxbai-embed-large","embeddings":[[\(arr)]]}
        """.data(using: .utf8)!
        let vec = try expectNotNil(OllamaEmbedResponse.decode(json))
        try expectEqual(vec.dim, 1024)
    }

    s.test("Ollama error response (model doesn't support embeddings) returns nil") {
        // This is the actual error shape probed at planning time for
        // gemma4_2b. Defensive nil so the spike runner surfaces the
        // failure to the user clearly.
        let json = """
        {"error": "this model does not support embeddings"}
        """.data(using: .utf8)!
        try expectNil(OllamaEmbedResponse.decode(json))
    }

    s.test("Ollama response with empty embeddings array returns nil") {
        let json = """
        {"model": "mxbai-embed-large", "embeddings": []}
        """.data(using: .utf8)!
        try expectNil(OllamaEmbedResponse.decode(json))
    }

    // MARK: - Request body builders

    s.test("Kobold request body builder produces the canonical /v1/embeddings shape") {
        let body = KoboldEmbeddingsRequest.body(input: "alpha beta gamma")
        let decoded = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        try expectEqual(decoded["input"] as? String, "alpha beta gamma")
    }

    s.test("Ollama request body builder includes model + input") {
        let body = OllamaEmbedRequest.body(model: "mxbai-embed-large", input: "alpha beta")
        let decoded = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        try expectEqual(decoded["model"] as? String, "mxbai-embed-large")
        try expectEqual(decoded["input"] as? String, "alpha beta")
    }

    return s
}
