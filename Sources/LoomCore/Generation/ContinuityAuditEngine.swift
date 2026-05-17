import Foundation

/// Extracts continuity claims from one scene. The seam the audit
/// engine drives — `OllamaContinuityExtractor` in production, a stub
/// in tests.
public protocol ContinuityClaimExtracting {
    func extract(
        scenePose: String,
        sceneId: String,
        completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
    )
}

extension OllamaContinuityExtractor: ContinuityClaimExtracting {}

/// Continuity Audit (L10) — Phase B, the engine orchestrator.
///
/// Drives the whole pipeline end to end for one on-demand audit:
///
/// 1. **Extract** — one extractor call per scene, sequential, claims
///    accumulated. A scene whose extraction fails is skipped (a
///    partial audit beats none).
/// 2. **Ground** — resolve every claim's subject to a canonical entity
///    (`ContinuitySubjectResolver`).
/// 3. **Retrieve** — narrow to candidate-conflict pairs
///    (`ContinuityConflictRetrieval`).
/// 4. **Adjudicate** — one writer call per pair, sequential; a
///    `contradiction` verdict becomes a finding. A pair whose
///    adjudication fails is skipped.
/// 5. **Knowledge check** — deterministic knowledge-before-reveal
///    violations (`ContinuityKnowledgeCheck`).
/// 6. **Assemble + store** — findings written to `ContinuityAuditStore`
///    (status carried forward across re-audits).
///
/// Mirrors `OutlineDraftCoordinator`'s recursive-async stepping and
/// `onMain` marshalling. One audit at a time.
///
/// **Not yet wired (Phase B tail):** the `ContinuityClaimFilter` pass
/// (dedup + evidence validation) needs a live embedder; the engine
/// runs without it for now — the filter is built and unit-tested, the
/// async embed orchestration is the remaining wire-up.
public final class ContinuityAuditEngine {

    public struct SceneInput {
        public let id: String
        public let prose: String
        public init(id: String, prose: String) {
            self.id = id
            self.prose = prose
        }
    }

    /// Posted when an audit starts. `userInfo: ["sceneCount": Int]`.
    public static let didStartNotification = Notification.Name("LoomContinuityAuditEngine.didStart")
    /// Posted when an audit finishes. `userInfo: ["findingCount": Int, "error": Error?]`.
    public static let didFinishNotification = Notification.Name("LoomContinuityAuditEngine.didFinish")

    private let extractor: ContinuityClaimExtracting
    private let adjudicationProvider: OllamaCallProvider
    private let entities: [ContinuitySubjectResolver.KnownEntity]
    private let similarity: (String, String) -> Double

    public private(set) var isRunning = false

    // Run-scoped state (one audit at a time).
    private var scenes: [SceneInput] = []
    private var projectURL: URL = URL(fileURLWithPath: "/")
    private var completion: ((Result<[ContinuityFinding], Error>) -> Void)?
    private var claims: [ContinuityAudit.Claim] = []
    private var pairs: [ContinuityConflictRetrieval.CandidatePair] = []
    private var findings: [ContinuityFinding] = []

    public init(
        extractor: ContinuityClaimExtracting,
        adjudicationProvider: OllamaCallProvider,
        entities: [ContinuitySubjectResolver.KnownEntity],
        similarity: @escaping (String, String) -> Double = ContinuityAuditEngine.tokenJaccard
    ) {
        self.extractor = extractor
        self.adjudicationProvider = adjudicationProvider
        self.entities = entities
        self.similarity = similarity
    }

    /// Run a whole-manuscript audit. `scenes` must be in narrative
    /// order. `completion` fires once with the assembled findings (or
    /// an error if the audit could not start / store).
    public func audit(
        scenes: [SceneInput],
        projectURL: URL,
        completion: @escaping (Result<[ContinuityFinding], Error>) -> Void
    ) {
        guard !isRunning else {
            completion(.failure(AuditError.alreadyRunning))
            return
        }
        isRunning = true
        self.scenes = scenes
        self.projectURL = projectURL
        self.completion = completion
        self.claims = []
        self.pairs = []
        self.findings = []

        NotificationCenter.default.post(
            name: Self.didStartNotification, object: self,
            userInfo: ["sceneCount": scenes.count])

        extractScene(0)
    }

    public enum AuditError: Error { case alreadyRunning }

    // MARK: - Stage 1: extraction

    private func extractScene(_ index: Int) {
        guard index < scenes.count else {
            extractionDone()
            return
        }
        let scene = scenes[index]
        extractor.extract(scenePose: scene.prose, sceneId: scene.id) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                switch result {
                case .success(let sceneClaims):
                    self.claims.append(contentsOf: sceneClaims)
                case .failure(let error):
                    DebugLog.shared.write("[continuity-audit] scene \(scene.id) extraction failed: \(error) — skipped")
                }
                self.extractScene(index + 1)
            }
        }
    }

    // MARK: - Stage 2-3: ground + retrieve

    private func extractionDone() {
        claims = ContinuitySubjectResolver.ground(claims: claims, entities: entities)
        let sceneOrder = scenes.map(\.id)
        pairs = ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: sceneOrder)
        DebugLog.shared.write("[continuity-audit] \(claims.count) claims → \(pairs.count) candidate pairs")
        adjudicatePair(0)
    }

    // MARK: - Stage 4: adjudication

    private func adjudicatePair(_ index: Int) {
        guard index < pairs.count else {
            adjudicationDone()
            return
        }
        let pair = pairs[index]
        let prompt = ContinuityAudit.buildAdjudicationPrompt(earlier: pair.earlier, later: pair.later)
        adjudicationProvider.call(
            prompt: prompt,
            schema: ContinuityAudit.adjudicationJSONSchema(),
            options: OllamaChatOptions(temperature: 0.2)
        ) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                switch result {
                case .success(let raw):
                    if let adj = try? ContinuityAudit.parseAdjudication(raw),
                       let finding = ContinuityFindingAssembly.finding(pair: pair, adjudication: adj) {
                        self.findings.append(finding)
                    }
                case .failure(let error):
                    DebugLog.shared.write("[continuity-audit] pair \(index) adjudication failed: \(error) — skipped")
                }
                self.adjudicatePair(index + 1)
            }
        }
    }

    // MARK: - Stage 5-6: knowledge check + store

    private func adjudicationDone() {
        let sceneOrder = scenes.map(\.id)
        let violations = ContinuityKnowledgeCheck.violations(
            claims: claims, sceneOrder: sceneOrder, similarity: similarity)
        findings.append(contentsOf: violations.map(ContinuityFindingAssembly.finding(knowledgeViolation:)))

        var storeError: Error? = nil
        do {
            try ContinuityAuditStore.replaceFindings(findings, in: projectURL)
        } catch {
            storeError = error
            DebugLog.shared.write("[continuity-audit] store write failed: \(error)")
        }
        finish(storeError.map { .failure($0) } ?? .success(findings))
    }

    private func finish(_ result: Result<[ContinuityFinding], Error>) {
        guard isRunning else { return }
        isRunning = false
        let count = (try? result.get().count) ?? 0
        NotificationCenter.default.post(
            name: Self.didFinishNotification, object: self,
            userInfo: ["findingCount": count, "error": (try? result.get()) == nil])
        let done = completion
        completion = nil
        done?(result)
    }

    // MARK: - Helpers

    /// Run `work` on the main thread (inline when already on it, so
    /// the recursive stepping stays deterministic for synchronous
    /// test stubs — the `OutlineDraftCoordinator` posture).
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Default proposition-similarity for the knowledge check — token
    /// Jaccard. The engine can be given an embedding-backed closure
    /// instead for sharper matching.
    public static func tokenJaccard(_ a: String, _ b: String) -> Double {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let x = tokens(a), y = tokens(b)
        if x.isEmpty && y.isEmpty { return 1 }
        let union = x.union(y).count
        return union == 0 ? 0 : Double(x.intersection(y).count) / Double(union)
    }
}
