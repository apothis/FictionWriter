import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #8 / LOOM_NSFW.md §2.5 — Sphiratrioth lorebook-as-active-
/// scenario starter pack.
///
/// The pattern (sphiratrioth on HuggingFace, validated in LOOM_RESEARCH §S):
/// default LLMs have a "positive bias" — they soften, cut away, fade to
/// black. Lorebook entries with "WILL INSTANTLY [ACTION]" phrasing,
/// group-weighted outcomes, and sticky persistence across scene shifts
/// counter this. Loom's Phase 2 lorebook schema shipped `group/weight/
/// sticky` specifically to host this pattern (HANDOFF §11 #8).
///
/// This phase lands the curated starter pack + an idempotent installer
/// the user invokes from the Bible inspector. The data is the
/// load-bearing piece; the UI button is honest-smoke glue.
func phase4SphiratriothStarterPackTests() -> TestSuite {
    let s = TestSuite("Phase4SphiratriothStarterPack")

    // MARK: - Pack content

    s.test("starter pack is a non-empty curated list") {
        try expectFalse(SphiratriothStarterPack.entries.isEmpty)
        // Sanity: at least 6 entries so the pattern shows
        // (anti-bias + sticky + at least one weighted group).
        try expectTrue(SphiratriothStarterPack.entries.count >= 6)
    }

    s.test("every starter-pack entry carries the [sph] name prefix") {
        // The prefix is how the installer detects already-present
        // entries without colliding with user-authored lorebook names.
        for entry in SphiratriothStarterPack.entries {
            try expectTrue(
                entry.name.hasPrefix("[sph]"),
                "entry must be [sph]-prefixed; got '\(entry.name)'"
            )
        }
    }

    s.test("pack contains at least one anti-positive-bias constant entry") {
        // Always-on, top-of-prompt, no keys — the canonical
        // anti-fade-to-black countermeasure.
        let constants = SphiratriothStarterPack.entries.filter {
            $0.activationMode == .constant
        }
        try expectFalse(constants.isEmpty, "pack must include constant-mode anti-bias entries")
    }

    s.test("pack contains at least one sticky scenario anchor") {
        let sticky = SphiratriothStarterPack.entries.filter { $0.sticky }
        try expectFalse(sticky.isEmpty, "pack must include sticky scenario entries (LOOM_NSFW §2.5)")
    }

    s.test("pack contains at least one weighted-group outcome bucket") {
        // Group-weighted entries are the Roll-Outcome substrate
        // (LOOM_MEMORY §B3). At minimum the pack should expose one
        // group with multiple weighted entries summing to a positive
        // total weight.
        let groups = Dictionary(grouping: SphiratriothStarterPack.entries.filter { $0.group != nil }) {
            $0.group!
        }
        try expectFalse(groups.isEmpty, "pack must include at least one weighted group")
        for (groupName, entries) in groups {
            try expectTrue(entries.count >= 2, "group '\(groupName)' must have >=2 entries to roll over")
            let totalWeight = entries.reduce(0) { $0 + ($1.weight ?? 0) }
            try expectTrue(totalWeight > 0, "group '\(groupName)' total weight must be positive")
        }
    }

    // MARK: - Installer (session integration)

    s.test("installSphiratriothStarterPack adds every entry to an empty lorebook") {
        let session = makeSession()
        try expectTrue(session.project.bible.lorebook.isEmpty)
        let added = session.installSphiratriothStarterPack()
        try expectEqual(added, SphiratriothStarterPack.entries.count)
        try expectEqual(session.project.bible.lorebook.count, SphiratriothStarterPack.entries.count)
    }

    s.test("re-installing on top of an installed pack adds zero new entries") {
        let session = makeSession()
        _ = session.installSphiratriothStarterPack()
        let countAfterFirst = session.project.bible.lorebook.count
        let addedSecond = session.installSphiratriothStarterPack()
        try expectEqual(addedSecond, 0, "second install should be a no-op")
        try expectEqual(session.project.bible.lorebook.count, countAfterFirst)
    }

    s.test("install fills in missing entries after user deletions") {
        let session = makeSession()
        let packCount = SphiratriothStarterPack.entries.count
        _ = session.installSphiratriothStarterPack()
        // User deletes two sphiratrioth entries.
        let victims = session.project.bible.lorebook
            .filter { $0.name.hasPrefix("[sph]") }
            .prefix(2)
        for v in victims { session.deleteLorebookEntry(id: v.id) }
        try expectEqual(session.project.bible.lorebook.count, packCount - 2)
        // Re-install fills the two gaps. Note: install is naive
        // additive-by-name — no tombstones — so deleted entries DO
        // come back. That's the documented behaviour.
        let added = session.installSphiratriothStarterPack()
        try expectEqual(added, 2)
        try expectEqual(session.project.bible.lorebook.count, packCount)
    }

    s.test("installing on a lorebook with unrelated user entries leaves them untouched") {
        let session = makeSession()
        let userEntry = session.addLorebookEntry(name: "My world rule")
        _ = session.installSphiratriothStarterPack()
        // User's entry still present + unchanged.
        let stillThere = session.project.bible.lorebook.first { $0.id == userEntry.id }
        let unwrapped = try expectNotNil(stillThere)
        try expectEqual(unwrapped.name, "My world rule")
    }

    return s
}

// MARK: - Helpers

private func makeSession() -> ProjectSession {
    let project = Project(title: "T")
    return ProjectSession(project: project, url: nil)
}
