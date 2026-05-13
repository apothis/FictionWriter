import Foundation
@testable import LoomCore

/// Pure-data tests for query-text extraction from a PromptContext.
/// The generation coordinator runs this against its just-built
/// PromptContext to determine what text to embed for style-RAG
/// retrieval. Per-mode shape:
///
/// - continueProse → last N words before cursor (the "scene-in-progress")
/// - expand / rewrite / rewriteVoice / rewriteTense / rewritePOV /
///   rewriteLength / showDontTell → the selected text
/// - brainstorm / critique / bridge / describe / nameSuggest → nil
///   (these modes don't generate prose to imitate a style)
func phase5RetrievalQueryBuilderTests() -> TestSuite {
    let s = TestSuite("Phase5RetrievalQueryBuilder")

    func makeContext(
        mode: GenerationMode,
        prose: String,
        cursorOffset: Int? = nil,
        selection: NSRange? = nil
    ) -> PromptContext {
        let scene = Scene.empty(id: UUID(), title: "S")
        var sceneCopy = scene
        sceneCopy.prose = prose
        var p = Project(title: "T")
        p.manuscript.orphanedSceneIds = [scene.id]
        return PromptContext(
            mode: mode, project: p, scenes: [scene.id: sceneCopy],
            currentSceneId: scene.id,
            cursorOffset: cursorOffset ?? (prose as NSString).length,
            selectionRange: selection, modelName: nil,
            contextBudgetTokens: 8192, replyBudgetTokens: 1024
        )
    }

    // MARK: - continueProse

    s.test("continueProse with sufficient prose returns last N words") {
        let prose = (1...50).map { "w\($0)" }.joined(separator: " ")
        let q = RetrievalQueryBuilder.queryText(for: makeContext(mode: .continueProse, prose: prose), lastWords: 10)
        let qWords = q!.split(whereSeparator: { $0.isWhitespace })
        try expectEqual(qWords.count, 10)
        try expectEqual(qWords.last.map(String.init), "w50")
    }

    s.test("continueProse with short prose returns all of it") {
        let prose = "Five words right here total."
        let q = RetrievalQueryBuilder.queryText(for: makeContext(mode: .continueProse, prose: prose), lastWords: 100)
        try expectEqual(q, prose)
    }

    s.test("continueProse with empty prose returns nil") {
        let q = RetrievalQueryBuilder.queryText(for: makeContext(mode: .continueProse, prose: ""), lastWords: 10)
        try expectNil(q)
    }

    s.test("continueProse with cursor mid-prose uses prose up to the cursor") {
        let prose = "First sentence. Second sentence. Third sentence after cursor."
        // Cursor after "Second sentence." → 32 chars in
        let cursorOffset = (prose as NSString).range(of: "Second sentence.").upperBound
        let q = RetrievalQueryBuilder.queryText(
            for: makeContext(mode: .continueProse, prose: prose, cursorOffset: cursorOffset),
            lastWords: 100
        )
        // Should not contain text after the cursor.
        try expectFalse(q!.contains("Third"))
        try expectTrue(q!.contains("Second"))
    }

    // MARK: - Selection-based modes

    s.test("expand with selection returns the selected substring") {
        let prose = "A red car raced down the empty road."
        let sel = NSRange(location: 2, length: 7) // "red car"
        let q = RetrievalQueryBuilder.queryText(
            for: makeContext(mode: .expand, prose: prose, selection: sel),
            lastWords: 100
        )
        try expectEqual(q, "red car")
    }

    s.test("rewrite with selection returns the selected substring") {
        let prose = "She walked slowly into the kitchen."
        let sel = NSRange(location: 4, length: 13)  // "walked slowly"
        let q = RetrievalQueryBuilder.queryText(
            for: makeContext(mode: .rewrite, prose: prose, selection: sel),
            lastWords: 100
        )
        try expectEqual(q, "walked slowly")
    }

    s.test("rewriteVoice, rewriteTense, rewritePOV, rewriteLength, showDontTell all use selection") {
        let prose = "She walked into the room."
        let sel = NSRange(location: 0, length: 10)  // "She walked"
        for mode in [GenerationMode.rewriteVoice, .rewriteTense, .rewritePOV, .rewriteLength, .showDontTell] {
            let q = RetrievalQueryBuilder.queryText(
                for: makeContext(mode: mode, prose: prose, selection: sel),
                lastWords: 100
            )
            try expectEqual(q, "She walked", "\(mode.rawValue) failed")
        }
    }

    s.test("expand with no selection returns nil (no query possible)") {
        let q = RetrievalQueryBuilder.queryText(
            for: makeContext(mode: .expand, prose: "x", selection: nil),
            lastWords: 100
        )
        try expectNil(q)
    }

    // MARK: - Non-applicable modes

    s.test("brainstorm, critique, bridge, describe, nameSuggest all return nil") {
        let prose = "Some prose here."
        for mode in [GenerationMode.brainstorm, .critique, .bridge, .describe, .nameSuggest] {
            let q = RetrievalQueryBuilder.queryText(
                for: makeContext(mode: mode, prose: prose),
                lastWords: 100
            )
            try expectTrue(q == nil, "\(mode.rawValue) should not produce a query (got \(q ?? "nil"))")
        }
    }

    // MARK: - Edge cases

    s.test("missing scene id returns nil") {
        var ctx = makeContext(mode: .continueProse, prose: "Some prose here.")
        ctx = PromptContext(
            mode: .continueProse, project: ctx.project, scenes: ctx.scenes,
            currentSceneId: nil, cursorOffset: 0, selectionRange: nil,
            modelName: nil, contextBudgetTokens: 8192, replyBudgetTokens: 1024
        )
        try expectNil(RetrievalQueryBuilder.queryText(for: ctx, lastWords: 100))
    }

    return s
}
