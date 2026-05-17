import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 3: composing a project's assigned
/// styles into prompt text. `StyleLibrary.resolve` (ids → styles) and
/// `StylePrompt.render` (styles → a prompt block, genre and register
/// in separate sections with register last). LOOM_PLANNED_PROJECT §6.
func plannedProjectStylePromptTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStylePrompt")

    func genre(_ name: String) -> Style {
        Style(
            name: name, type: .genre, descriptor: "\(name) descriptor.",
            constraints: ["\(name) constraint."]
        )
    }
    func register(_ name: String) -> Style {
        Style(
            name: name, type: .register, descriptor: "\(name) descriptor.",
            constraints: ["\(name) constraint."]
        )
    }

    // MARK: - resolve

    s.test("resolve maps ids to styles in the requested order, dropping unknown ids") {
        let a = genre("A")
        let b = register("B")
        let resolved = StyleLibrary.resolve([b.id, a.id, UUID()], in: [a, b])
        try expectEqual(resolved.map(\.name), ["B", "A"])
    }

    s.test("resolve of no ids is empty") {
        try expectEqual(
            StyleLibrary.resolve([], in: StyleLibrary.builtInStarters).count, 0
        )
    }

    // MARK: - render

    s.test("rendering no styles yields an empty string") {
        try expectEqual(StylePrompt.render([]), "")
    }

    s.test("a genre style renders its name, descriptor, and constraints") {
        let text = StylePrompt.render([genre("Noir")])
        try expectTrue(text.contains("Noir"))
        try expectTrue(text.contains("Noir descriptor."))
        try expectTrue(text.contains("Noir constraint."))
    }

    s.test("genre and register render in separate sections, register last") {
        let text = StylePrompt.render([register("Hardcore"), genre("Sci-Fi")])
        let genreAt = try expectNotNil(text.range(of: "Sci-Fi"))
        let registerAt = try expectNotNil(text.range(of: "Hardcore"))
        try expectTrue(
            genreAt.lowerBound < registerAt.lowerBound,
            "the genre section must come before the register section"
        )
    }

    s.test("the register section is framed as hard constraints") {
        let text = StylePrompt.render([register("Hardcore")])
        try expectTrue(text.lowercased().contains("hard constraint"))
    }

    s.test("exemplar passages are included when a style has them") {
        var st = genre("Noir")
        st.exemplars = ["The rain hadn't stopped since Tuesday."]
        let text = StylePrompt.render([st])
        try expectTrue(text.contains("The rain hadn't stopped since Tuesday."))
    }

    return s
}
