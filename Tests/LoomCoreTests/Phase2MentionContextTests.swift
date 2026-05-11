import Foundation
@testable import LoomCore

/// Phase 2 #10 (pure-data, detection) — `@`-mention context detection.
/// Given a prose body + cursor offset, decide whether the cursor is
/// in an `@xxx` context (the user is typing a mention). The editor's
/// completion-popover trigger uses this to decide whether to show
/// suggestions.
func phase2MentionContextTests() -> TestSuite {
    let s = TestSuite("Phase2MentionContext")

    s.test("cursor immediately after @ → context with empty query") {
        let prose = "Hello @"
        let ctx = EntityMentionContext.detect(in: prose, cursorOffset: prose.count)
        let c = try expectNotNil(ctx)
        try expectEqual(c.partialQuery, "")
        try expectEqual(c.replacementRange.location, 6)
        try expectEqual(c.replacementRange.length, 1)   // just the @
    }

    s.test("cursor after @M → context with query 'M'") {
        let prose = "Hello @M"
        let ctx = EntityMentionContext.detect(in: prose, cursorOffset: prose.count)
        let c = try expectNotNil(ctx)
        try expectEqual(c.partialQuery, "M")
        try expectEqual(c.replacementRange.length, 2)   // @M
    }

    s.test("cursor after @Mia → context with query 'Mia'") {
        let prose = "Hello @Mia"
        let ctx = EntityMentionContext.detect(in: prose, cursorOffset: prose.count)
        let c = try expectNotNil(ctx)
        try expectEqual(c.partialQuery, "Mia")
        try expectEqual(c.replacementRange.length, 4)   // @Mia
    }

    s.test("cursor after @ then space → NOT a mention context (space ended it)") {
        let prose = "Hello @ "
        try expectNil(EntityMentionContext.detect(in: prose, cursorOffset: prose.count))
    }

    s.test("cursor in plain prose (no @) → nil") {
        let prose = "Hello Mia walked in."
        try expectNil(EntityMentionContext.detect(in: prose, cursorOffset: prose.count))
    }

    s.test("an @ in the middle of a word (email-like) is NOT a mention context") {
        // The @ must be preceded by whitespace, newline, or BOL —
        // otherwise an address like `foo@bar` triggers completions
        // every time, which is wrong.
        let prose = "Contact foo@bar"
        try expectNil(EntityMentionContext.detect(in: prose, cursorOffset: prose.count))
    }

    s.test("mention at BOL works") {
        let prose = "@Sherlock"
        let ctx = EntityMentionContext.detect(in: prose, cursorOffset: prose.count)
        let c = try expectNotNil(ctx)
        try expectEqual(c.partialQuery, "Sherlock")
        try expectEqual(c.replacementRange.location, 0)
    }

    s.test("mention after newline works") {
        let prose = "Line one.\n@Mia"
        let ctx = EntityMentionContext.detect(in: prose, cursorOffset: prose.count)
        let c = try expectNotNil(ctx)
        try expectEqual(c.partialQuery, "Mia")
    }

    s.test("applyReplacement substitutes the @-range with the entity markdown") {
        let prose = "Hello @M"
        let id = UUID()
        let match = EntityAutocompleteMatch(
            ref: BibleEntityRef(category: .characters, id: id),
            displayName: "Mia"
        )
        let ctx = try expectNotNil(EntityMentionContext.detect(in: prose, cursorOffset: prose.count))
        let result = ctx.applyReplacement(in: prose, with: match)
        try expectEqual(result.prose, "Hello [Mia](#entity/\(id.uuidString.lowercased()))")
        // Cursor lands at the end of the inserted markdown.
        try expectEqual(result.cursorOffset, result.prose.count)
    }

    return s
}
