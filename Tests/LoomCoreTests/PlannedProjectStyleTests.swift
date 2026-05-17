import Foundation
@testable import LoomCore

/// Planned Project mode — the `Style` model: a typed, mixable genre /
/// register record that conditions generation. LOOM_PLANNED_PROJECT
/// §5. Includes the lazy-decode forward-load contract.
func plannedProjectStyleTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStyle")

    s.test("StyleType has genre and register and round-trips") {
        try expectEqual(Set(StyleType.allCases), [.genre, .register])
        for t in StyleType.allCases {
            let data = try JSONEncoder().encode(t)
            try expectEqual(try JSONDecoder().decode(StyleType.self, from: data), t)
        }
    }

    s.test("Style round-trips through Codable") {
        let style = Style(
            name: "Noir", type: .genre,
            descriptor: "Terse, shadowed prose.",
            constraints: ["Short declarative sentences."],
            exemplars: ["The rain hadn't stopped since Tuesday."],
            isBuiltIn: true
        )
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(Style.self, from: data)
        try expectEqual(back, style)
    }

    s.test("Style init defaults collections empty and isBuiltIn false") {
        let style = Style(name: "X", type: .register, descriptor: "d")
        try expectEqual(style.constraints, [])
        try expectEqual(style.exemplars, [])
        try expectTrue(!style.isBuiltIn)
    }

    s.test("forward-load: a minimal Style JSON decodes with field defaults") {
        // A minimal payload — only the core fields present. Future
        // fields must land additively, so the optional ones default.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Noir","type":"genre"}
        """
        let style = try JSONDecoder().decode(Style.self, from: Data(json.utf8))
        try expectEqual(style.name, "Noir")
        try expectEqual(style.type, .genre)
        try expectEqual(style.descriptor, "")
        try expectEqual(style.constraints, [])
        try expectEqual(style.exemplars, [])
        try expectTrue(!style.isBuiltIn)
    }

    s.test("built-in starter styles have deterministic, unique ids") {
        // The derivation is a pure function — same inputs, same id.
        try expectEqual(
            StyleLibrary.stableStyleID(name: "Noir", type: .genre),
            StyleLibrary.stableStyleID(name: "Noir", type: .genre)
        )
        // Distinct name or type → distinct id.
        try expectTrue(
            StyleLibrary.stableStyleID(name: "Noir", type: .genre)
                != StyleLibrary.stableStyleID(name: "Terse", type: .register)
        )
        try expectTrue(
            StyleLibrary.stableStyleID(name: "Noir", type: .genre)
                != StyleLibrary.stableStyleID(name: "Noir", type: .register)
        )
        // Every starter id is unique — no collisions across the library.
        let ids = StyleLibrary.builtInStarters.map(\.id)
        try expectEqual(Set(ids).count, ids.count)
        // The starter library uses the derivation — not random UUIDs,
        // so a project's assignedStyleIds survive an app relaunch.
        for style in StyleLibrary.builtInStarters {
            try expectEqual(
                style.id,
                StyleLibrary.stableStyleID(name: style.name, type: style.type)
            )
        }
    }

    return s
}
