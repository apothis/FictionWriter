import Foundation
@testable import LoomCore

/// Sub-step 1.i.A — pure recent-prose extraction. Given a scene's prose
/// + a cursor offset + a budget in chars (proxied tokens), return the
/// substring up to (but not including) the cursor that fits the budget,
/// preferring paragraph-boundary truncation over mid-sentence cuts.
func phase1RecentProseWindowTests() -> TestSuite {
    let s = TestSuite("Phase1RecentProseWindow")

    s.test("returns full prose when within budget") {
        let prose = "Para one.\n\nPara two."
        let result = RecentProseWindow.extract(from: prose, cursorOffset: prose.count, charBudget: 10_000)
        try expectEqual(result, prose)
    }

    s.test("returns prose up to cursor when cursor is mid-prose") {
        let prose = "before cursor here. and stuff after."
        let cursor = "before cursor here.".count
        let result = RecentProseWindow.extract(from: prose, cursorOffset: cursor, charBudget: 10_000)
        try expectEqual(result, "before cursor here.")
    }

    s.test("truncates to last N chars when over budget") {
        // 200-char prose, 80-char budget; result is at most 80 chars and
        // is a suffix of the prose-up-to-cursor.
        let prose = String(repeating: "abc def ghi.\n\n", count: 20)
        let result = RecentProseWindow.extract(from: prose, cursorOffset: prose.count, charBudget: 80)
        try expectLessThan(result.count, 81)
        try expectTrue(prose.hasSuffix(result), "result should be a suffix of the source prose")
    }

    s.test("prefers paragraph-boundary truncation over mid-sentence cut") {
        // 4 paragraphs of equal length. Budget fits the last 2.x paragraphs.
        // Result should start at a paragraph boundary, not mid-line.
        let p1 = "Para one with some words here."
        let p2 = "Para two with some other words."
        let p3 = "Para three with even more text."
        let p4 = "Para four ends the prose."
        let prose = [p1, p2, p3, p4].joined(separator: "\n\n")
        let cursor = prose.count
        // Budget allows ~2.5 paragraphs (~95 chars). Expect to cut at a
        // paragraph break, returning the trailing 2 or 3 paragraphs whole.
        let result = RecentProseWindow.extract(from: prose, cursorOffset: cursor, charBudget: 95)
        try expectTrue(result.hasSuffix(p4))
        // The result should start at the beginning of one of the paragraphs.
        let begins = result.hasPrefix(p2) || result.hasPrefix(p3) || result.hasPrefix(p4)
        try expectTrue(begins, "result must begin at a paragraph boundary; got: \(result)")
    }

    s.test("empty prose returns empty string") {
        let result = RecentProseWindow.extract(from: "", cursorOffset: 0, charBudget: 1000)
        try expectEqual(result, "")
    }

    s.test("cursor at start returns empty string") {
        let result = RecentProseWindow.extract(from: "some prose", cursorOffset: 0, charBudget: 1000)
        try expectEqual(result, "")
    }

    s.test("cursor offset clamped to prose length") {
        let prose = "five words"
        let result = RecentProseWindow.extract(from: prose, cursorOffset: 9999, charBudget: 1000)
        try expectEqual(result, prose)
    }

    return s
}
