import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #6 — pure-data choice list for the Rewrite sub-mode
/// picker. The tray surfaces these as an `NSMenu` that pops up when
/// the Rewrite button is clicked; each `RewriteSubModeChoice` carries
/// the menu label + the `GenerationMode` to fire + the descriptor
/// that should land in `PromptContext.perCallInstruction` (or
/// `usesTrayInstruction = true` for Voice, which falls back to the
/// user's typed instruction-field text).
///
/// Order is the menu's visual order — Voice first, then Tense
/// presets, then Length presets, then generic. AppKit glue inserts
/// `NSMenuItem.separator()` between distinct `mode` groups.
func phase4RewriteSubModePickerTests() -> TestSuite {
    let s = TestSuite("Phase4RewriteSubModePicker")

    s.test("choices include exactly one Voice entry routing tray-instruction text through") {
        let voice = RewriteSubModeMenuBuilder.choices.filter { $0.mode == .rewriteVoice }
        try expectEqual(voice.count, 1)
        try expectTrue(voice[0].usesTrayInstruction,
            "the Voice entry must route the user's typed text from the tray instruction field")
        try expectNil(voice[0].descriptor)
    }

    s.test("choices include Past + Present tense presets with the right descriptors") {
        let tense = RewriteSubModeMenuBuilder.choices.filter { $0.mode == .rewriteTense }
        try expectEqual(tense.count, 2)
        try expectEqual(tense[0].descriptor, "past")
        try expectEqual(tense[1].descriptor, "present")
        try expectFalse(tense[0].usesTrayInstruction)
        try expectFalse(tense[1].usesTrayInstruction)
    }

    s.test("choices include the §4.4 length presets (50%/80%/120%/150%)") {
        let length = RewriteSubModeMenuBuilder.choices.filter { $0.mode == .rewriteLength }
        let descriptors = length.map(\.descriptor)
        try expectEqual(descriptors, ["50%", "80%", "120%", "150%"])
        for c in length {
            try expectFalse(c.usesTrayInstruction)
        }
    }

    s.test("choices include a generic-rewrite escape hatch with nil descriptor") {
        let generic = RewriteSubModeMenuBuilder.choices.filter { $0.mode == .rewrite }
        try expectEqual(generic.count, 1)
        try expectNil(generic[0].descriptor)
        try expectFalse(generic[0].usesTrayInstruction)
    }

    s.test("length-choice descriptor list is exactly the §4.4 presets") {
        let length = RewriteSubModeMenuBuilder.choices.filter { $0.mode == .rewriteLength }
        let descriptors = length.compactMap(\.descriptor)
        try expectEqual(descriptors, ["50%", "80%", "120%", "150%"])
    }

    s.test("choices total exactly the four mode groups in expected order") {
        // Voice(1) + Tense(2) + Length(4) + Generic(1) = 8.
        let modes = RewriteSubModeMenuBuilder.choices.map(\.mode)
        try expectEqual(modes, [
            .rewriteVoice,
            .rewriteTense, .rewriteTense,
            .rewriteLength, .rewriteLength, .rewriteLength, .rewriteLength,
            .rewrite,
        ])
    }

    s.test("every choice has a non-empty user-visible title") {
        for c in RewriteSubModeMenuBuilder.choices {
            try expectFalse(c.title.isEmpty,
                "choice for mode=\(c.mode.rawValue) descriptor=\(c.descriptor ?? "nil") has empty title")
        }
    }

    return s
}
