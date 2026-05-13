import Foundation

/// Request/response parsers for the embedding endpoints the Phase 5
/// RAG spike calls (LOOM_RAG_SPIKE.md §6 S3). Pure-data — HTTP
/// transport lives in `Tools/RagSpike`. Defensive `nil` returns on
/// decode failure so the spike runner can surface the error to the
/// user clearly rather than crashing on a bad payload.

public enum KoboldEmbeddingsRequest {
    public static func body(input: String) -> Data {
        let payload: [String: Any] = ["input": input]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

public enum KoboldEmbeddingsResponse {
    private struct Wire: Decodable {
        let data: [Item]
        struct Item: Decodable { let embedding: [Float] }
    }

    public static func decode(_ data: Data) -> EmbeddingVector? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        guard let first = wire.data.first, !first.embedding.isEmpty else { return nil }
        return EmbeddingVector(values: first.embedding)
    }
}

public enum OllamaEmbedRequest {
    public static func body(model: String, input: String) -> Data {
        let payload: [String: Any] = ["model": model, "input": input]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

public enum OllamaEmbedResponse {
    private struct Wire: Decodable {
        let embeddings: [[Float]]?
        let error: String?
    }

    public static func decode(_ data: Data) -> EmbeddingVector? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        guard wire.error == nil else { return nil }
        guard let first = wire.embeddings?.first, !first.isEmpty else { return nil }
        return EmbeddingVector(values: first)
    }
}
