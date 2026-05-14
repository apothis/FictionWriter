import Foundation

// Phase 8.a §6.1 — embedder abstraction + spike orchestrator. Each
// candidate embedder (StyleDistance, Wegmann, LUAR via Python
// subprocess; mxbai via Ollama HTTP) conforms to `SpikeEmbedder`. The
// orchestrator iterates the fixture set, gathers vectors, and produces
// a cosine matrix + register-axis + style-axis separation scores.

public protocol SpikeEmbedder {
    /// Stable identifier — used in report headers + diagnostics.
    var id: String { get }
    /// Synchronous embed. Returns nil on failure (subprocess crash,
    /// HTTP error, malformed response). The orchestrator surfaces a
    /// fail-fast error if any fixture embeds to nil — we'd rather see
    /// the spike fail loudly than carry a zero-vector through the
    /// matrix and skew the scores.
    func embed(_ text: String) -> EmbeddingVector?
}

public enum SpikeOrchestratorError: Error, Equatable {
    case embedFailed(fixtureId: String)
}

public struct SpikeOrchestratorResult {
    public let matrix: CosineMatrix
    public let registerScore: SeparationScore
    public let styleAxisScore: SeparationScore
}

public enum SpikeOrchestrator {
    /// Build the cosine matrix + scores from a fixture set + embedder.
    /// Order in `matrix.labels` matches the input fixture order, so
    /// the caller controls the row/column layout.
    public static func cosineMatrix(
        fixtures: [SceneExemplarFixture],
        embedder: SpikeEmbedder
    ) throws -> SpikeOrchestratorResult {
        var vectors: [(label: String, vector: EmbeddingVector)] = []
        vectors.reserveCapacity(fixtures.count)
        for fixture in fixtures {
            guard let vec = embedder.embed(fixture.body) else {
                throw SpikeOrchestratorError.embedFailed(fixtureId: fixture.id)
            }
            vectors.append((label: fixture.id, vector: vec))
        }
        let matrix = CosineMatrixAnalysis.build(vectors: vectors)
        let registerMap = Dictionary(uniqueKeysWithValues:
            fixtures.map { ($0.id, $0.register) })
        let styleAxisMap = Dictionary(uniqueKeysWithValues:
            fixtures.map { ($0.id, $0.styleAxis) })
        let registerScore = CosineMatrixAnalysis.separationScore(matrix: matrix) {
            registerMap[$0] ?? ""
        }
        let styleAxisScore = CosineMatrixAnalysis.separationScore(matrix: matrix) {
            styleAxisMap[$0] ?? ""
        }
        return SpikeOrchestratorResult(
            matrix: matrix,
            registerScore: registerScore,
            styleAxisScore: styleAxisScore
        )
    }
}
