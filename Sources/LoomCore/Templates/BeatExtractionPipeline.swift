import Foundation

/// Protocol for Pass-A beat extraction. Production wraps Ollama
/// gemma4_2b via `OllamaBeatExtractor`; tests inject a stub.
///
/// Mirrors the Phase 4 `LedgerExtractor` shape: async completion
/// callback, error path on transport / parse failure. Per the
/// async-callback memory, real implementations MUST hop to a worker
/// thread and call the completion later — never synchronously inside
/// the extractor method.
public protocol BeatExtractor {
    func extractSkeleton(
        from sourceProse: String,
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    )
}

/// Loads a `TemplateScene` from disk, runs Pass A via the injected
/// extractor, and persists the resulting `ExtractedSceneSkeleton`
/// as the `.beats.json` sidecar.
///
/// Single public entry point — `extractAndPersist(templateId:completion:)` —
/// matches the Phase 5 A2 `ingestReference` shape. The caller
/// (`AppState.extractTemplateScene` in production) handles thread
/// hopping; the pipeline assumes its async completion will arrive
/// on whichever queue the injected extractor uses.
///
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md) §9 (7.b.2).
public final class BeatExtractionPipeline {
    public let projectURL: URL
    public let extractor: BeatExtractor

    public init(projectURL: URL, extractor: BeatExtractor) {
        self.projectURL = projectURL
        self.extractor = extractor
    }

    public enum PipelineError: Error, Equatable {
        case templateLoadFailed(String)
        case sidecarWriteFailed(String)
    }

    public func extractAndPersist(
        templateId: UUID,
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    ) {
        // Load the template scene body from disk. Synchronous; cheap.
        // Failure is treated as a stale-id error and surfaced
        // immediately (no extractor call).
        let template: TemplateScene
        do {
            template = try TemplateSceneStorage.loadTemplate(id: templateId, in: projectURL)
        } catch {
            DebugLog.shared.write("[template] extract: load failed id=\(templateId) error=\(error)")
            completion(.failure(PipelineError.templateLoadFailed(String(describing: error))))
            return
        }

        // Strong-self capture is load-bearing. Without it the URLSession
        // callback can fire into a deallocated pipeline if the caller
        // doesn't hold a reference. Mirrors the Phase 4 LedgerExtractor
        // lifetime-test finding.
        extractor.extractSkeleton(from: template.body) { result in
            switch result {
            case .success(let rawSkeleton):
                // Normalize before persisting: sort beats chronologically,
                // merge near-duplicate adjacent beats, re-index. Curbs the
                // monologue-exemplar over-segmentation that drives Pass-B
                // repetition (2026-05-22 test5 run).
                let skeleton = BeatExtraction.normalizeSkeleton(rawSkeleton)
                do {
                    try TemplateSceneStorage.saveSkeleton(
                        skeleton, for: template.id, in: self.projectURL
                    )
                    DebugLog.shared.write("[template] extract: saved id=\(template.id) beats=\(skeleton.beats.count)")
                    completion(.success(skeleton))
                } catch {
                    DebugLog.shared.write("[template] extract: sidecar write failed id=\(template.id) error=\(error)")
                    completion(.failure(PipelineError.sidecarWriteFailed(String(describing: error))))
                }
            case .failure(let error):
                DebugLog.shared.write("[template] extract: extractor failed id=\(template.id) error=\(error)")
                completion(.failure(error))
            }
        }
    }
}
