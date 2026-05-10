import Foundation
@testable import LoomCore

/// Phase 2 polish: Author's Note spliced INTO the recent-prose layer
/// N lines back from the cursor — NovelAI's A/N convention. The pure
/// helper is tested here; integration with PromptBuilder is covered in
/// Phase1PromptBuilderLayersTests.
func phase1AuthorsNoteInjectorTests() -> TestSuite {
    let s = TestSuite("Phase1AuthorsNoteInjector")

    s.test("empty author's note returns prose unchanged") {
        let prose = "Line one.\nLine two.\nLine three."
        let out = AuthorsNoteInjector.inject(authorsNote: "", into: prose, depthLines: 2)
        try expectEqual(out, prose)
    }

    s.test("whitespace-only author's note returns prose unchanged") {
        let prose = "Line one.\nLine two."
        let out = AuthorsNoteInjector.inject(authorsNote: "   \n  ", into: prose, depthLines: 2)
        try expectEqual(out, prose)
    }

    s.test("depthLines = 0 places the AN at the very end (closest to cursor)") {
        let prose = "Para one.\n\nPara two."
        let out = AuthorsNoteInjector.inject(authorsNote: "terse style", into: prose, depthLines: 0)
        try expectTrue(out.hasSuffix("[terse style]"), "AN should land at the end when depth=0")
    }

    s.test("depthLines = 2 places the AN with 2 lines of prose between it and the end") {
        let prose = "L1\nL2\nL3\nL4\nL5"
        let out = AuthorsNoteInjector.inject(authorsNote: "AN", into: prose, depthLines: 2)
        // Expect: L1\nL2\nL3 + bracket + L4\nL5
        let bracketIdx = try expectNotNil(out.range(of: "[AN]")?.lowerBound)
        let afterBracket = out[bracketIdx...].suffix(out.distance(from: bracketIdx, to: out.endIndex))
        try expectTrue(afterBracket.contains("L4"))
        try expectTrue(afterBracket.contains("L5"))
        try expectFalse(afterBracket.contains("L3"), "L3 should land BEFORE the AN bracket")
    }

    s.test("depthLines >= line count places AN at the very top") {
        let prose = "L1\nL2"
        let out = AuthorsNoteInjector.inject(authorsNote: "AN", into: prose, depthLines: 99)
        try expectTrue(out.hasPrefix("[AN]"), "AN should land at the start when depth exceeds line count")
    }

    s.test("bracketed convention is used regardless of input formatting") {
        let prose = "prose"
        let out = AuthorsNoteInjector.inject(authorsNote: "terse, vivid", into: prose, depthLines: 0)
        try expectTrue(out.contains("[terse, vivid]"))
    }

    s.test("trims leading/trailing whitespace from the note before bracketing") {
        let prose = "prose"
        let out = AuthorsNoteInjector.inject(authorsNote: "  trim me  ", into: prose, depthLines: 0)
        try expectTrue(out.contains("[trim me]"))
        try expectFalse(out.contains("[  trim me  ]"))
    }

    return s
}
