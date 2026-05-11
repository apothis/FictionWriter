import Foundation
@testable import LoomCore

/// Phase 2.5 (#10 follow-on) — `EntityReference.scanWithRanges`
/// returns every entity-link match in prose, paired with its NSRange.
/// The hover-preview popover uses this to know which character
/// positions cover an entity-link region, so a mouseMoved at any
/// glyph in that span lights up the hover.
func phase2EntityReferenceRangesTests() -> TestSuite {
    let s = TestSuite("Phase2EntityReferenceRanges")

    s.test("scanWithRanges returns the NSRange of each link in prose") {
        let id1 = UUID()
        let id2 = UUID()
        let m1 = EntityReference(category: .characters, id: id1, displayName: "Mia").markdown
        let m2 = EntityReference(category: .characters, id: id2, displayName: "Bob").markdown
        let prose = "Hi \(m1) and \(m2). End."
        let hits = EntityReference.scanWithRanges(in: prose)
        try expectEqual(hits.count, 2)
        try expectEqual(hits[0].reference.id, id1)
        let firstStart = (prose as NSString).range(of: m1).location
        try expectEqual(hits[0].range.location, firstStart)
        try expectEqual(hits[0].range.length, (m1 as NSString).length)
        try expectEqual(hits[1].reference.id, id2)
    }

    s.test("scanWithRanges returns [] for prose with no entity links") {
        try expectEqual(EntityReference.scanWithRanges(in: "Plain prose."), [])
    }

    s.test("referenceAtLocation finds the link covering a character index") {
        let id = UUID()
        let m = EntityReference(category: .characters, id: id, displayName: "Mia").markdown
        let prose = "Hello \(m) end."
        let mStart = (prose as NSString).range(of: m).location
        let mLength = (m as NSString).length
        // Inside the link.
        try expectEqual(EntityReference.referenceAt(location: mStart, in: prose)?.reference.id, id)
        try expectEqual(EntityReference.referenceAt(location: mStart + 1, in: prose)?.reference.id, id)
        try expectEqual(EntityReference.referenceAt(location: mStart + mLength - 1, in: prose)?.reference.id, id)
        // Outside it.
        try expectNil(EntityReference.referenceAt(location: 0, in: prose))
        try expectNil(EntityReference.referenceAt(location: mStart + mLength + 1, in: prose))
    }

    return s
}
