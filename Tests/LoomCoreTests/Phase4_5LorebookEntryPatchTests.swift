import Foundation
@testable import LoomCore

/// Phase 4.5 Session 3 — `LorebookEntryPatch` is the JSON contract
/// for JS→Swift partial updates to a `LorebookEntry`. Mirrors
/// `CharacterPatch` semantics: every field optional, `nil` means
/// "leave alone", a present value sets exactly.
///
/// Collection semantics:
/// - `nil`: leave the array unchanged.
/// - `[]`: clear it.
/// - `[x, y]`: replace entirely.
///
/// Optional scalar fields (`depth: Int?`, `group: String?`,
/// `weight: Int?`): `nil` in the patch leaves the existing value
/// alone — clearing requires a different intent (out of scope for
/// Session 3, not currently surfaced in the workspace UI).
func phase4_5LorebookEntryPatchTests() -> TestSuite {
    let s = TestSuite("Phase4_5LorebookEntryPatch")

    func baseline() -> LorebookEntry {
        LorebookEntry(
            id: UUID(),
            name: "scenario:kink",
            content: "weighted kink scenario",
            activationMode: .keyed,
            keys: ["kink", "scenario"],
            secondaryKeys: ["nsfw"],
            enabled: true,
            priority: 50,
            positionMode: .top,
            depth: nil,
            maxRecentScenesScanned: 3,
            group: "kink_outcome",
            weight: 25,
            sticky: false
        )
    }

    // MARK: - apply(to:)

    s.test("empty patch leaves the entry entirely unchanged") {
        let e = baseline()
        let patch = LorebookEntryPatch()
        try expectEqual(patch.apply(to: e), e)
    }

    s.test("patch with name only changes name") {
        let e = baseline()
        let patch = LorebookEntryPatch(name: "scenario:other")
        let applied = patch.apply(to: e)
        try expectEqual(applied.name, "scenario:other")
        try expectEqual(applied.content, e.content)
        try expectEqual(applied.activationMode, e.activationMode)
    }

    s.test("patch with content changes content") {
        let e = baseline()
        let patch = LorebookEntryPatch(content: "new payload")
        try expectEqual(patch.apply(to: e).content, "new payload")
    }

    s.test("patch with activationMode changes activation mode") {
        let e = baseline()
        let patch = LorebookEntryPatch(activationMode: .constant)
        try expectEqual(patch.apply(to: e).activationMode, .constant)
    }

    s.test("patch with positionMode changes positionMode") {
        let e = baseline()
        let patch = LorebookEntryPatch(positionMode: .depthN)
        try expectEqual(patch.apply(to: e).positionMode, .depthN)
    }

    s.test("patch with all scalar power-user knobs applies them") {
        let e = baseline()
        let patch = LorebookEntryPatch(
            name: "x",
            content: "y",
            activationMode: .constant,
            enabled: false,
            priority: 100,
            positionMode: .depthN,
            depth: 5,
            maxRecentScenesScanned: 10,
            group: "outcome_b",
            weight: 80,
            sticky: true
        )
        let applied = patch.apply(to: e)
        try expectEqual(applied.name, "x")
        try expectEqual(applied.content, "y")
        try expectEqual(applied.activationMode, .constant)
        try expectEqual(applied.enabled, false)
        try expectEqual(applied.priority, 100)
        try expectEqual(applied.positionMode, .depthN)
        try expectEqual(applied.depth, 5)
        try expectEqual(applied.maxRecentScenesScanned, 10)
        try expectEqual(applied.group, "outcome_b")
        try expectEqual(applied.weight, 80)
        try expectEqual(applied.sticky, true)
    }

    // MARK: - Array fields

    s.test("patch with keys replaces the array") {
        let e = baseline()
        let patch = LorebookEntryPatch(keys: ["new", "keys"])
        try expectEqual(patch.apply(to: e).keys, ["new", "keys"])
    }

    s.test("patch with empty keys clears the array") {
        let e = baseline()
        let patch = LorebookEntryPatch(keys: [])
        try expectEqual(patch.apply(to: e).keys, [])
    }

    s.test("patch with nil keys leaves keys alone") {
        let e = baseline()
        let patch = LorebookEntryPatch(name: "rename only")
        try expectEqual(patch.apply(to: e).keys, e.keys)
    }

    s.test("patch with secondaryKeys replaces the array") {
        let e = baseline()
        let patch = LorebookEntryPatch(secondaryKeys: ["a", "b"])
        try expectEqual(patch.apply(to: e).secondaryKeys, ["a", "b"])
    }

    // MARK: - Bool + Int fields

    s.test("patch with enabled=false disables the entry") {
        let e = baseline()
        let patch = LorebookEntryPatch(enabled: false)
        try expectEqual(patch.apply(to: e).enabled, false)
    }

    s.test("patch with sticky=true sets sticky") {
        let e = baseline()
        let patch = LorebookEntryPatch(sticky: true)
        try expectEqual(patch.apply(to: e).sticky, true)
    }

    // MARK: - Codable

    s.test("empty patch round-trips through JSON cleanly") {
        let patch = LorebookEntryPatch()
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(LorebookEntryPatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("populated patch round-trips with every field preserved") {
        let patch = LorebookEntryPatch(
            name: "x",
            content: "y",
            activationMode: .constant,
            keys: ["k1"],
            secondaryKeys: ["k2"],
            enabled: false,
            priority: 100,
            positionMode: .depthN,
            depth: 5,
            maxRecentScenesScanned: 10,
            group: "g",
            weight: 80,
            sticky: true
        )
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(LorebookEntryPatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("absent JSON keys decode as nil (bridge sends only changed fields)") {
        let json = "{\"name\":\"x\"}"
        let decoded = try JSONDecoder().decode(LorebookEntryPatch.self, from: Data(json.utf8))
        try expectEqual(decoded.name, "x")
        try expectNil(decoded.content)
        try expectNil(decoded.keys)
        try expectNil(decoded.enabled)
    }

    return s
}
