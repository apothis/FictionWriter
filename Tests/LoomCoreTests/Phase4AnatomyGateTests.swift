import Foundation
@testable import LoomCore

/// Intimate-anatomy gate — `Character.intimateAnatomy` is injected
/// only when the scene is depicted (explicitness ≥ onScreen) AND the
/// character is shown undressed, detected per-character.
func phase4AnatomyGateTests() -> TestSuite {
    let s = TestSuite("Phase4AnatomyGate")

    func mira() -> Character {
        var c = Character(name: "Mira", aliases: ["Mir"])
        c.intimateAnatomy = "detailed anatomy notes"
        return c
    }

    // MARK: schema

    s.test("anatomy fields default empty and round-trip") {
        try expectEqual(Character.empty(name: "X").intimateAnatomy, "")
        try expectEqual(Character.empty(name: "X").apparentAnatomy, "")
        var c = mira()
        c.apparentAnatomy = "tall, broad-shouldered build"
        let data = try JSONEncoder.loomPretty.encode(c)
        let back = try JSONDecoder.loom.decode(Character.self, from: data)
        try expectEqual(back.intimateAnatomy, "detailed anatomy notes")
        try expectEqual(back.apparentAnatomy, "tall, broad-shouldered build")
    }

    s.test("apparent anatomy is always in the bible block — even a fadeToBlack scene") {
        var project = Project(title: "T")
        var c = Character(name: "Mira")
        c.apparentAnatomy = "athletic, full-figured"
        c.intimateAnatomy = "concealed detail text"
        project.bible.characters = [c]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sc = scene
        sc.explicitnessLevel = .fadeToBlack
        sc.prose = "Mira crossed the room."
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project, scenes: [scene.id: sc],
            currentSceneId: scene.id, cursorOffset: (sc.prose as NSString).length,
            selectionRange: nil, modelName: nil, contextBudgetTokens: 8192,
            replyBudgetTokens: 1024
        ))
        // Apparent anatomy shows; concealed anatomy does not.
        try expectTrue(result.fullPrompt.contains("athletic, full-figured"))
        try expectFalse(result.fullPrompt.contains("concealed detail text"))
    }

    // MARK: AnatomyGate

    s.test("a character with no anatomy notes never injects") {
        let plain = Character(name: "Mira")
        try expectFalse(AnatomyGate.shouldInject(
            character: plain, sceneProseSoFar: "Mira was naked.", explicitnessLevel: .graphic
        ))
    }

    s.test("a non-depicted scene never injects, even when undressed") {
        for level in [ExplicitnessLevel.fadeToBlack, .suggestive] {
            try expectFalse(AnatomyGate.shouldInject(
                character: mira(), sceneProseSoFar: "Mira was naked.", explicitnessLevel: level
            ))
        }
    }

    s.test("a depicted scene with the character undressed injects") {
        for level in [ExplicitnessLevel.onScreen, .graphic, .extreme] {
            try expectTrue(AnatomyGate.shouldInject(
                character: mira(), sceneProseSoFar: "Mira stood there, naked.", explicitnessLevel: level
            ))
        }
    }

    s.test("a depicted scene with the character still clothed does not inject") {
        try expectFalse(AnatomyGate.shouldInject(
            character: mira(), sceneProseSoFar: "Mira crossed the room and sat down.",
            explicitnessLevel: .graphic
        ))
    }

    s.test("an explicit undress marker injects without a prose keyword") {
        let m = mira()
        // No undress word in the prose — the heuristic would miss it.
        let prose = "Mira and Cole had finally stopped talking."
        try expectFalse(AnatomyGate.shouldInject(
            character: m, sceneProseSoFar: prose, explicitnessLevel: .graphic
        ))
        try expectTrue(AnatomyGate.shouldInject(
            character: m, sceneProseSoFar: prose, explicitnessLevel: .graphic,
            explicitlyUndressedIds: [m.id]
        ))
    }

    s.test("an explicit marker still respects the explicitness gate") {
        let m = mira()
        try expectFalse(AnatomyGate.shouldInject(
            character: m, sceneProseSoFar: "anything", explicitnessLevel: .fadeToBlack,
            explicitlyUndressedIds: [m.id]
        ))
    }

    s.test("an alias also triggers the undress detection") {
        try expectTrue(AnatomyGate.isUndressed(
            character: mira(), in: "Mir was undressed by then."
        ))
    }

    s.test("name and undress term in DIFFERENT paragraphs do not co-trigger") {
        let prose = "Mira walked in.\n\nSomeone, somewhere, was naked."
        try expectFalse(AnatomyGate.isUndressed(character: mira(), in: prose))
    }

    s.test("the unlock is sticky — an earlier undressing still counts") {
        let prose = "Mira slipped off her dress, naked now.\n\nLater they talked quietly."
        try expectTrue(AnatomyGate.isUndressed(character: mira(), in: prose))
    }

    s.test("per-character: one character undressed does not unlock another") {
        var cole = Character(name: "Cole")
        cole.intimateAnatomy = "cole's anatomy"
        let prose = "Mira was naked.\n\nCole stayed fully dressed by the door."
        try expectTrue(AnatomyGate.shouldInject(
            character: mira(), sceneProseSoFar: prose, explicitnessLevel: .graphic
        ))
        try expectFalse(AnatomyGate.shouldInject(
            character: cole, sceneProseSoFar: prose, explicitnessLevel: .graphic
        ))
    }

    // MARK: PromptBuilder wiring

    s.test("a depicted scene injects only the undressed character's anatomy") {
        var project = Project(title: "T")
        var cole = Character(name: "Cole")
        cole.intimateAnatomy = "cole anatomy text"
        project.bible.characters = [mira(), cole]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sc = scene
        sc.explicitnessLevel = .graphic
        sc.prose = "Mira was naked.\n\nCole stayed dressed by the door."
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project, scenes: [scene.id: sc],
            currentSceneId: scene.id, cursorOffset: (sc.prose as NSString).length,
            selectionRange: nil, modelName: nil, contextBudgetTokens: 8192,
            replyBudgetTokens: 1024
        ))
        try expectTrue(result.fullPrompt.contains("detailed anatomy notes"))
        try expectFalse(result.fullPrompt.contains("cole anatomy text"))
        try expectNotNil(result.chiclets.first { $0.sourceKind == .intimateAnatomy })
    }

    s.test("a fadeToBlack scene injects no anatomy at all") {
        var project = Project(title: "T")
        project.bible.characters = [mira()]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sc = scene
        sc.explicitnessLevel = .fadeToBlack
        sc.prose = "Mira was naked."
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project, scenes: [scene.id: sc],
            currentSceneId: scene.id, cursorOffset: (sc.prose as NSString).length,
            selectionRange: nil, modelName: nil, contextBudgetTokens: 8192,
            replyBudgetTokens: 1024
        ))
        try expectFalse(result.fullPrompt.contains("detailed anatomy notes"))
        try expectNil(result.chiclets.first { $0.sourceKind == .intimateAnatomy })
    }

    return s
}
