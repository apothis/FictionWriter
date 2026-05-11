import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 #6 (UI layer) — honest smoke for the Project tab's
/// narrative-style pill-pickers (POV / Tense / Direction /
/// Vocabulary / Explicitness).
///
/// Mounts the controller, drives each picker programmatically via
/// the public `setX(_:)` test-surface, and asserts the session
/// reflects the change. Picker rendering itself isn't unit-tested;
/// the underlying ProjectSession setters are pinned in
/// Phase2NarrativeStyleTests.
func phase2ProjectSettingsPickersTests() -> TestSuite {
    let s = TestSuite("Phase2ProjectSettingsPickers")

    func freshSession() -> ProjectSession {
        ProjectSession(project: Project(title: "T"))
    }

    s.test("controller mounts with all five narrative-style pickers wired") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        try expectNotNil(vc.povPicker)
        try expectNotNil(vc.tensePicker)
        try expectNotNil(vc.directionKindPicker)
        try expectNotNil(vc.vocabularyPicker)
        try expectNotNil(vc.explicitnessPicker)
    }

    s.test("each picker initialises to the current project settings") {
        var project = Project(title: "T")
        project.settings.pov = .firstPerson
        project.settings.tense = .present
        project.settings.writingDirection.kind = .erotica
        project.settings.writingDirection.register = .crude
        project.settings.writingDirection.explicitnessLevel = .extreme

        let session = ProjectSession(project: project)
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        try expectEqual(vc.selectedPOV, .firstPerson)
        try expectEqual(vc.selectedTense, .present)
        try expectEqual(vc.selectedDirectionKind, .erotica)
        try expectEqual(vc.selectedVocabulary, .crude)
        try expectEqual(vc.selectedExplicitness, .extreme)
    }

    s.test("setPOV(_:) on the controller routes through to the session") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        vc.setPOV(.secondPerson)
        try expectEqual(session.project.settings.pov, .secondPerson)
        try expectEqual(vc.selectedPOV, .secondPerson)
    }

    s.test("setTense(_:) on the controller routes through to the session") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        vc.setTense(.present)
        try expectEqual(session.project.settings.tense, .present)
        try expectEqual(vc.selectedTense, .present)
    }

    s.test("setDirectionKind(_:) routes through and reflects on the picker") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        vc.setDirectionKind(.porn)
        try expectEqual(session.project.settings.writingDirection.kind, .porn)
        try expectEqual(vc.selectedDirectionKind, .porn)
    }

    s.test("setVocabulary(_:) routes through and reflects on the picker") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        vc.setVocabulary(.earthy)
        try expectEqual(session.project.settings.writingDirection.register, .earthy)
        try expectEqual(vc.selectedVocabulary, .earthy)
    }

    s.test("setExplicitness(_:) routes through and reflects on the picker") {
        let session = freshSession()
        let vc = ProjectSettingsTabViewController(session: session)
        _ = vc.view
        vc.setExplicitness(.graphic)
        try expectEqual(session.project.settings.writingDirection.explicitnessLevel, .graphic)
        try expectEqual(vc.selectedExplicitness, .graphic)
    }

    return s
}
