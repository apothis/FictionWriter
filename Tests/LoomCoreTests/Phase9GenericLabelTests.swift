import Foundation
@testable import LoomCore

/// Generic-person-label filter. Stage D occasionally normalises a
/// candidate — typically a first-person narrator GLiNER tagged — into
/// a generic role label ("The Character", "The Narrator") rather than
/// a real name. Such a canonical name is never bible-worthy; it is
/// dropped after normalisation. Sibling of the anatomy block-list.
func phase9GenericLabelTests() -> TestSuite {
    let s = TestSuite("Phase9GenericLabel")

    s.test("rejects generic role labels as canonical names") {
        try expectTrue(EntityDiscovery.isGenericPersonLabel("The Character"))
        try expectTrue(EntityDiscovery.isGenericPersonLabel("The Narrator"))
        try expectTrue(EntityDiscovery.isGenericPersonLabel("Narrator"))
        try expectTrue(EntityDiscovery.isGenericPersonLabel("the protagonist"))
        try expectTrue(EntityDiscovery.isGenericPersonLabel("A Stranger"))
    }

    s.test("rejects bare generic person nouns") {
        try expectTrue(EntityDiscovery.isGenericPersonLabel("the man"))
        try expectTrue(EntityDiscovery.isGenericPersonLabel("Woman"))
    }

    s.test("keeps real proper names") {
        try expectFalse(EntityDiscovery.isGenericPersonLabel("Marcus"))
        try expectFalse(EntityDiscovery.isGenericPersonLabel("Della"))
        try expectFalse(EntityDiscovery.isGenericPersonLabel("Marius Thorn"))
        try expectFalse(EntityDiscovery.isGenericPersonLabel("Miss Abby"))
    }

    s.test("a proper noun alongside a generic word keeps the entity") {
        // "Captain Vance" — "captain" is generic-ish but "Vance" is not.
        try expectFalse(EntityDiscovery.isGenericPersonLabel("Captain Vance"))
    }

    s.test("empty / determiner-only inputs are not labels") {
        try expectFalse(EntityDiscovery.isGenericPersonLabel(""))
        try expectFalse(EntityDiscovery.isGenericPersonLabel("   "))
        try expectFalse(EntityDiscovery.isGenericPersonLabel("the"))
    }

    return s
}
