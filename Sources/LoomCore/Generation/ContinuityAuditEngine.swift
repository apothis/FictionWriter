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
    /// Fallback proposition similarity (token Jaccard). When an
    /// `embedder` is supplied the run uses an embedding-backed cosine
    /// instead, falling back to this for any text not embedded.
    private let baseSimilarity: (String, String) -> Double
    /// Optional. When present, extracted claims are run through
    /// `ContinuityClaimFilterPipeline` (dedup + evidence validation)
    /// and the knowledge check gets an embedding-backed similarity.
    private let embedder: KoboldEmbedding?
    /// Optional §25 Part B same-fact judge. When present, the
    /// knowledge stage replaces the legacy similarity-threshold
    /// matching with a world-state fact ledger: claims are clustered
    /// into canonical fact nodes via the judge, and a
    /// `knowledge_state` reference becomes a candidate when its fact
    /// node's `firstAppearanceScene` lands after the reference. When
    /// nil the engine uses the legacy path. Both paths still feed the
    /// LLM adjudicator as a confirmation backstop.
    private let judge: SameFactJudging?

    public private(set) var isRunning = false

    // Run-scoped state (one audit at a time).
    private var scenes: [SceneInput] = []
    private var projectURL: URL = URL(fileURLWithPath: "/")
    private var completion: ((Result<[ContinuityFinding], Error>) -> Void)?
    private var claims: [ContinuityAudit.Claim] = []
    private var pairs: [ContinuityConflictRetrieval.CandidatePair] = []
    private var knowledgeCandidates: [ContinuityKnowledgeCheck.Violation] = []
    private var findings: [ContinuityFinding] = []
    /// The similarity in force for this run — embedding-backed when an
    /// embedder ran, else `baseSimilarity`.
    private var activeSimilarity: (String, String) -> Double = ContinuityAuditEngine.tokenJaccard
    /// True once `activeSimilarity` is embedding-backed — retrieval then
    /// clusters on cosine (a higher threshold) instead of the default
    /// content-word Jaccard.
    private var usingEmbeddingSimilarity = false
    /// Embeddings of every surviving claim value, captured from the
    /// `ContinuityClaimFilterPipeline` pass. Used by §25 Part B's
    /// per-knowledge-claim cosine ranking. Empty when no embedder ran.
    private var claimEmbeddings: [String: [Float]] = [:]

    public init(
        extractor: ContinuityClaimExtracting,
        adjudicationProvider: OllamaCallProvider,
        entities: [ContinuitySubjectResolver.KnownEntity],
        embedder: KoboldEmbedding? = nil,
        judge: SameFactJudging? = nil,
        similarity: @escaping (String, String) -> Double = ContinuityAuditEngine.tokenJaccard
    ) {
        self.extractor = extractor
        self.adjudicationProvider = adjudicationProvider
        self.entities = entities
        self.embedder = embedder
        self.judge = judge
        self.baseSimilarity = similarity
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
        self.knowledgeCandidates = []
        self.findings = []
        self.activeSimilarity = baseSimilarity
        self.usingEmbeddingSimilarity = false

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

    // MARK: - Stage 2-3: ground + filter + retrieve

    private func extractionDone() {
        claims = ContinuitySubjectResolver.ground(claims: claims, entities: entities)
        guard let embedder = embedder, !claims.isEmpty else {
            retrieveAndAdjudicate()
            return
        }
        // Filter pass — dedup + evidence validation — and reuse the
        // embeddings for an embedding-backed knowledge-check similarity.
        var proseByScene: [String: String] = [:]
        for scene in scenes { proseByScene[scene.id] = scene.prose }
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims, sceneProseByScene: proseByScene
        ) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                self.claims = result.claims
                if !result.embeddings.isEmpty {
                    let emb = result.embeddings
                    let base = self.baseSimilarity
                    self.activeSimilarity = { a, b in
                        if let va = emb[a], let vb = emb[b] {
                            return LedgerExtraction.cosineSimilarity(va, vb)
                        }
                        return base(a, b)
                    }
                    self.usingEmbeddingSimilarity = true
                    self.claimEmbeddings = emb
                }
                DebugLog.shared.write(
                    "[continuity-audit] claim-filter: -\(result.dedupDropped) dedup, -\(result.evidenceDropped) evidence")
                self.retrieveAndAdjudicate()
            }
        }
    }

    /// Cosine-similarity threshold for embedding-backed retrieval
    /// clustering — two claim values cluster (and so become a candidate
    /// pair) at/above this. A contradiction is two near-paraphrase
    /// claims that disagree on one element, so they stay well above it.
    /// The knowledge check uses a lower threshold of its own (a
    /// reference and its reveal are framed differently — §23).
    private static let retrievalCosineThreshold = 0.7

    private func retrieveAndAdjudicate() {
        let sceneOrder = scenes.map(\.id)
        pairs = usingEmbeddingSimilarity
            ? ContinuityConflictRetrieval.candidatePairs(
                claims: claims, sceneOrder: sceneOrder,
                similarity: activeSimilarity, threshold: Self.retrievalCosineThreshold)
            : ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: sceneOrder)
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

    // MARK: - Stage 5: knowledge check + adjudication

    /// §25 Part B (redesigned, 2026-05-20). For each knowledge_state
    /// claim, the check cosine-ranks non-knowledge claims and asks
    /// the same-fact judge on the top-K. Default K=10 — comfortably
    /// covers the real reveal (§24 measured ref↔reveal cosines at
    /// 0.73–0.94 — top-10 will contain it) while bounding cost to
    /// `knowledge_claims × K` LLM calls per audit.
    private static let partBTopK = 10

    private func adjudicationDone() {
        let sceneOrder = scenes.map(\.id)
        let ksCount = claims.filter { $0.type == .knowledgeState }.count
        if let judge = judge {
            let nonKnowledge = claims.filter { $0.type != .knowledgeState }
            let knowledgeClaims = claims.filter { $0.type == .knowledgeState }
            DebugLog.shared.write("[continuity-audit] Part B: per-k cosine top-\(Self.partBTopK) over \(nonKnowledge.count) candidate claims for \(ksCount) knowledge_state references …")
            ContinuityKnowledgeCheck.violations(
                knowledgeClaims: knowledgeClaims,
                candidateClaims: nonKnowledge,
                embeddings: claimEmbeddings,
                sceneOrder: sceneOrder,
                judge: judge,
                topK: Self.partBTopK
            ) { [weak self] violations in
                guard let self = self else { return }
                self.onMain {
                    self.knowledgeCandidates = violations
                    DebugLog.shared.write("[continuity-audit] Part B: \(ksCount) knowledge_state claims → \(violations.count) knowledge candidates")
                    for c in violations {
                        DebugLog.shared.write("[continuity-audit]   kcand ref@\(c.knowledgeClaim.sourceSceneId)=\"\(c.knowledgeClaim.value)\" reveal@\(c.revealClaim.sourceSceneId)=\"\(c.revealClaim.value)\"")
                    }
                    self.adjudicateKnowledge(0)
                }
            }
            return
        }
        // Legacy similarity-threshold path.
        knowledgeCandidates = ContinuityKnowledgeCheck.violations(
            claims: claims, sceneOrder: sceneOrder, similarity: activeSimilarity)
        DebugLog.shared.write("[continuity-audit] \(ksCount) knowledge_state claims → \(knowledgeCandidates.count) knowledge candidates")
        for c in knowledgeCandidates {
            DebugLog.shared.write("[continuity-audit]   kcand ref@\(c.knowledgeClaim.sourceSceneId)=\"\(c.knowledgeClaim.value)\" reveal@\(c.revealClaim.sourceSceneId)=\"\(c.revealClaim.value)\"")
        }
        adjudicateKnowledge(0)
    }

    private func adjudicateKnowledge(_ index: Int) {
        guard index < knowledgeCandidates.count else {
            storeAndFinish()
            return
        }
        let candidate = knowledgeCandidates[index]
        // Show each claim with a window of its real scene prose:
        // embedding cosine can't separate a real violation from a
        // topical look-alike, so the adjudicator needs the actual text.
        let refClaim = candidate.knowledgeClaim
        let revClaim = candidate.revealClaim
        let refContext = ContinuityAudit.evidenceContextWindow(
            quote: refClaim.evidenceQuote, in: prose(of: refClaim.sourceSceneId))
        let revContext = ContinuityAudit.evidenceContextWindow(
            quote: revClaim.evidenceQuote, in: prose(of: revClaim.sourceSceneId))
        let prompt = ContinuityAudit.buildKnowledgeAdjudicationPrompt(
            reference: refClaim, reveal: revClaim,
            referenceContext: refContext, revealContext: revContext)
        adjudicationProvider.call(
            prompt: prompt,
            schema: ContinuityAudit.knowledgeAdjudicationJSONSchema(),
            options: OllamaChatOptions(temperature: 0.2)
        ) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                switch result {
                case .success(let raw):
                    if let adj = try? ContinuityAudit.parseKnowledgeAdjudication(raw) {
                        DebugLog.shared.write("[continuity-audit] knowledge candidate \(index) verdict=\(adj.verdict.rawValue)")
                        if adj.verdict == .violation {
                            self.findings.append(ContinuityFindingAssembly.finding(
                                knowledgeViolation: candidate,
                                explanation: adj.explanation,
                                confidence: adj.confidence))
                        }
                    } else {
                        DebugLog.shared.write("[continuity-audit] knowledge candidate \(index) — adjudication parse failed")
                    }
                case .failure(let error):
                    DebugLog.shared.write("[continuity-audit] knowledge candidate \(index) adjudication failed: \(error) — skipped")
                }
                self.adjudicateKnowledge(index + 1)
            }
        }
    }

    // MARK: - Stage 6: store

    private func storeAndFinish() {
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

    /// The prose of a scene by id, or empty if the scene is unknown.
    private func prose(of sceneId: String) -> String {
        scenes.first { $0.id == sceneId }?.prose ?? ""
    }

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
