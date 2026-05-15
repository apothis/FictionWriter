import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — anatomy-descriptor block-list.
/// LOOM_ENTITY_DISCOVERY_SPIKE §4.6: NSFW prose tends to identify
/// otherwise-unnamed characters by anatomical / hair / skin features
/// ("the redhead", "the brunette", "the blonde", "the woman with X").
/// These are NOT bible-worthy promotions — the user already has a
/// permanent name for that character in their head; the prose is
/// just varying surface form. Block them at the gate.
///
/// The block-list only fires when the *canonical name* of the
/// proposed entity is **wholly** an anatomy descriptor. If the
/// descriptor co-occurs with a proper noun in the surrounding
/// evidence span, the proper noun wins and the entity is kept
/// (handled by the broader gate, not this filter).
func phase9AnatomyBlocklistTests() -> TestSuite {
    let s = TestSuite("Phase9AnatomyBlocklist")

    s.test("rejects bare anatomy descriptors as canonical names") {
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the redhead"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the brunette"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the blonde"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("redhead"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the blond"))
    }

    s.test("rejects descriptors regardless of case + leading determiner") {
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("The Redhead"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("REDHEAD"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("a redhead"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("  the redhead  "))
    }

    s.test("keeps proper-noun names even when adjacent to descriptors") {
        // Single proper noun: always keep.
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("Marius"))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("Liana Thorn"))
        // Proper noun + descriptor: keep (proper noun is the
        // referential anchor; descriptor is colour).
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("Marius the redhead"))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("Redhead Marius"))
    }

    s.test("keeps named roles + occupations that aren't anatomy") {
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("the doctor"))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("the captain"))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("the woman in red"))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("the stranger"))
    }

    s.test("rejects multi-word anatomy phrases") {
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the redheaded woman"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the blonde woman"))
        try expectTrue(EntityDiscovery.isAnatomyOnlyDescriptor("the brunette girl"))
    }

    s.test("handles edge cases: empty + whitespace + nil-like inputs") {
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor(""))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("   "))
        try expectFalse(EntityDiscovery.isAnatomyOnlyDescriptor("the"))
    }

    return s
}
