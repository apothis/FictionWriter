import Foundation
@testable import LoomCore

/// Phase 2 #7 (schema layer) — InjectionMode on Bible entities.
/// Per HANDOFF §9.1 row 7 + LOOM_MEMORY.md §A2.4 (BIBLE-keyed
/// injection): each entity carries its activation mode — .constant
/// (always injected, current behaviour) or .keyed (injected only
/// when the entity's name/alias appears in recent prose).
///
/// Default for Phase 2 entities is .constant so existing projects
/// keep their existing prompt-assembly behaviour. The .keyed mode
/// is the new affordance the user can opt into per entity.
///
/// Tests-first per the always-TDD memory contract.
func phase2InjectionModeTests() -> TestSuite {
    let s = TestSuite("Phase2InjectionMode")

    s.test("InjectionMode covers .constant + .keyed") {
        try expectEqual(Set(InjectionMode.allCases), [.constant, .keyed])
    }

    s.test("Character defaults injectionMode to .constant") {
        let c = Character(name: "Mia")
        try expectEqual(c.injectionMode, .constant)
    }

    s.test("Setting defaults injectionMode to .constant") {
        let st = Setting(name: "221B")
        try expectEqual(st.injectionMode, .constant)
    }

    s.test("BibleObject defaults injectionMode to .constant") {
        let o = BibleObject(name: "Pipe")
        try expectEqual(o.injectionMode, .constant)
    }

    s.test("Character with explicit injectionMode round-trips") {
        var c = Character(name: "Mia")
        c.injectionMode = .keyed
        let data = try JSONEncoder.loomPretty.encode(c)
        let back = try JSONDecoder.loom.decode(Character.self, from: data)
        try expectEqual(back.injectionMode, .keyed)
        try expectEqual(back, c)
    }

    s.test("Setting with explicit injectionMode round-trips") {
        var st = Setting(name: "221B")
        st.injectionMode = .keyed
        let data = try JSONEncoder.loomPretty.encode(st)
        let back = try JSONDecoder.loom.decode(Setting.self, from: data)
        try expectEqual(back.injectionMode, .keyed)
        try expectEqual(back, st)
    }

    s.test("BibleObject with explicit injectionMode round-trips") {
        var o = BibleObject(name: "Pipe")
        o.injectionMode = .keyed
        let data = try JSONEncoder.loomPretty.encode(o)
        let back = try JSONDecoder.loom.decode(BibleObject.self, from: data)
        try expectEqual(back.injectionMode, .keyed)
        try expectEqual(back, o)
    }

    s.test("Phase 1 Character JSON without injectionMode decodes with .constant — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Mia"
        }
        """
        let decoded = try JSONDecoder.loom.decode(Character.self, from: Data(json.utf8))
        try expectEqual(decoded.injectionMode, .constant)
    }

    s.test("Phase 1 Setting JSON without injectionMode decodes with .constant — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "221B"
        }
        """
        let decoded = try JSONDecoder.loom.decode(Setting.self, from: Data(json.utf8))
        try expectEqual(decoded.injectionMode, .constant)
    }

    s.test("Phase 1 BibleObject JSON without injectionMode decodes with .constant — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Pipe"
        }
        """
        let decoded = try JSONDecoder.loom.decode(BibleObject.self, from: Data(json.utf8))
        try expectEqual(decoded.injectionMode, .constant)
    }

    return s
}
