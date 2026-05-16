import Foundation

/// The entity-DETECTION step of discovery: scene prose → raw entity
/// mention candidates. Abstracted so the orchestrator can be tested
/// without ONNX and so detection can swap implementations.
public protocol EntityCandidateDetecting {
    func detectCandidates(
        in scenePose: String,
        completion: @escaping (Result<[EntityDiscovery.Candidate], Error>) -> Void
    )
}

/// Production entity detector: GLiNER, the native bidirectional NER
/// encoder. Replaces the generative-LLM Stage A2 — a tagger is
/// deterministic and cannot refuse or derail on explicit prose.
public final class GLiNERCandidateDetector: EntityCandidateDetecting {
    private let detector: GLiNERDetector
    private let queue = DispatchQueue(label: "com.loom.gliner.detect", qos: .userInitiated)

    /// GLiNER's label set for discovery — the `EntityDiscovery.Kind`
    /// raw values, so a detected label maps straight back to a `Kind`.
    static let labels = EntityDiscovery.Kind.allCases.map(\.rawValue)

    public init(detector: GLiNERDetector) {
        self.detector = detector
    }

    public func detectCandidates(
        in scenePose: String,
        completion: @escaping (Result<[EntityDiscovery.Candidate], Error>) -> Void
    ) {
        queue.async { [detector] in
            do {
                let entities = try detector.detect(text: scenePose, labels: Self.labels)
                completion(.success(Self.candidates(from: entities, sourceText: scenePose)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Map GLiNER entity spans to discovery candidates. The
    /// `firstSeenQuote` is the sentence enclosing the span — the
    /// evidence Stage D and the cosine-dedup need.
    static func candidates(
        from entities: [GLiNEREntity],
        sourceText: String
    ) -> [EntityDiscovery.Candidate] {
        let scalars = Array(sourceText.unicodeScalars)
        return entities.compactMap { entity in
            guard let kind = EntityDiscovery.Kind(rawValue: entity.label) else { return nil }
            return EntityDiscovery.Candidate(
                surface: entity.text,
                kind: kind,
                firstSeenQuote: enclosingSentence(
                    scalars: scalars, start: entity.start, end: entity.end
                )
            )
        }
    }

    /// The sentence (terminator-delimited run) containing the
    /// Unicode-scalar range `start..<end`, trimmed.
    static func enclosingSentence(
        scalars: [UnicodeScalar],
        start: Int,
        end: Int
    ) -> String {
        let boundaries: Set<UnicodeScalar> = [".", "!", "?", "\n"]
        var lo = min(start, scalars.count)
        while lo > 0, !boundaries.contains(scalars[lo - 1]) { lo -= 1 }
        var hi = min(end, scalars.count)
        while hi < scalars.count, !boundaries.contains(scalars[hi]) { hi += 1 }
        if hi < scalars.count { hi += 1 }  // include the terminator
        let slice = String(String.UnicodeScalarView(scalars[lo..<hi]))
        return slice.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
