import Foundation
@testable import LoomCore

/// Pass-A beat-extraction routing decision. After the 2026-05-22 Goetia
/// bake-off (Goetia 24B non-thinking: writer + GBNF produces a valid,
/// varied skeleton; every gemma4 extractor still free-forms the wrong
/// schema), Pass-A prefers the WRITER with GBNF over the Ollama
/// extractor. The Ollama extractor stays a best-effort fallback only
/// when no writer is configured.
func phase7PassARouteTests() -> TestSuite {
    let s = TestSuite("Phase7PassARoute")

    s.test("prefers the writer (GBNF) when a writer is configured — even if an extractor also exists") {
        try expectEqual(
            AppState.passARoute(hasWriterServer: true, hasExtractorServer: true),
            .writerGBNF
        )
        try expectEqual(
            AppState.passARoute(hasWriterServer: true, hasExtractorServer: false),
            .writerGBNF
        )
    }

    s.test("falls back to the Ollama extractor only when no writer is configured") {
        try expectEqual(
            AppState.passARoute(hasWriterServer: false, hasExtractorServer: true),
            .ollamaExtractor
        )
    }

    s.test("routes nowhere when neither server is configured") {
        try expectEqual(
            AppState.passARoute(hasWriterServer: false, hasExtractorServer: false),
            .none
        )
    }

    return s
}
