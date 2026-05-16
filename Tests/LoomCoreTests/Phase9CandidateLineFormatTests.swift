import Foundation
@testable import LoomCore

/// Phase 9 follow-up (2026-05-16) — Stage A2 line-based output.
/// Small models reliably emit a delimited line list but flake when
/// asked for a nested JSON array; Stage A2 now asks for one entity
/// per line, `kind | surface | quote`, parsed tolerantly.
func phase9CandidateLineFormatTests() -> TestSuite {
    let s = TestSuite("Phase9CandidateLineFormat")

    // MARK: - parseCandidateLines

    s.test("clean lines decode into candidates") {
        let raw = """
        character | Chantal | Chantal walked in.
        place | The Quay | The pub was called The Quay.
        object | Excalibur | He drew Excalibur.
        """
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 3)
        try expectEqual(cands[0].surface, "Chantal")
        try expectEqual(cands[0].kind, .character)
        try expectEqual(cands[0].firstSeenQuote, "Chantal walked in.")
        try expectEqual(cands[1].kind, .place)
        try expectEqual(cands[2].kind, .object)
    }

    s.test("blank lines and header noise are skipped") {
        let raw = """
        Here are the entities I found:

        character | Anders | Anders waved.

        """
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 1)
        try expectEqual(cands[0].surface, "Anders")
    }

    s.test("leading bullet / numbering markers are tolerated") {
        let raw = """
        - character | Mia | Mia opened the door.
        * place | Brussels | She flew to Brussels.
        2. object | The Necronomicon | He read The Necronomicon.
        """
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 3)
        try expectEqual(cands[0].surface, "Mia")
        try expectEqual(cands[1].surface, "Brussels")
        try expectEqual(cands[2].surface, "The Necronomicon")
    }

    s.test("an elaborated kind word still matches by substring") {
        let raw = """
        significant object | Excalibur | He drew Excalibur.
        named place | Brussels | She flew to Brussels.
        """
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 2)
        try expectEqual(cands[0].kind, .object)
        try expectEqual(cands[1].kind, .place)
    }

    s.test("lines with an unrecognised kind are skipped") {
        let raw = """
        character | Anders | q
        alien | Zorp | q
        """
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 1)
        try expectEqual(cands[0].surface, "Anders")
    }

    s.test("a pipe inside the quote is preserved (maxSplits)") {
        let raw = "character | Bob | He muttered \"a | b\" under his breath."
        let cands = EntityDiscovery.parseCandidateLines(raw)
        try expectEqual(cands.count, 1)
        try expectEqual(cands[0].firstSeenQuote, "He muttered \"a | b\" under his breath.")
    }

    s.test("empty input → empty result") {
        try expectEqual(EntityDiscovery.parseCandidateLines("").count, 0)
        try expectEqual(EntityDiscovery.parseCandidateLines("   \n  \n").count, 0)
    }

    // MARK: - buildCandidateListPrompt

    s.test("prompt includes the scene prose verbatim") {
        let prose = "Mia opened the door. Anders was there."
        let prompt = EntityDiscovery.buildCandidateListPrompt(
            scenePose: prose, knownEntityNames: []
        )
        try expectTrue(prompt.contains(prose))
    }

    s.test("prompt instructs proper-noun-only extraction") {
        let prompt = EntityDiscovery.buildCandidateListPrompt(
            scenePose: "...", knownEntityNames: []
        )
        try expectTrue(prompt.lowercased().contains("proper noun"))
    }

    s.test("prompt specifies the kind | surface | quote line format") {
        let prompt = EntityDiscovery.buildCandidateListPrompt(
            scenePose: "...", knownEntityNames: []
        )
        try expectTrue(prompt.contains("|"))
        try expectTrue(prompt.lowercased().contains("per line"))
        try expectTrue(prompt.contains("kind"))
        try expectTrue(prompt.contains("surface"))
    }

    s.test("prompt enumerates the known-entity exclusion list") {
        let prompt = EntityDiscovery.buildCandidateListPrompt(
            scenePose: "...", knownEntityNames: ["Mia", "Karim"]
        )
        try expectTrue(prompt.contains("Mia"))
        try expectTrue(prompt.contains("Karim"))
    }

    return s
}
