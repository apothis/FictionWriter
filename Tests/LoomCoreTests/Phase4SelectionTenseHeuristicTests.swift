import Foundation
@testable import LoomCore

/// Phase 4 §15.9 follow-on — heuristic classifier for the dominant
/// narrative tense of an arbitrary prose selection. Drives the
/// rewriteTense no-op-target guard: if the user picks "Tense — past"
/// on a selection the heuristic already classifies as `.past`, the
/// picker entry is disabled (and the click handler short-circuits with
/// a tray message). The §15.8 failure mode: both Qwen and Gemma,
/// asked to rewrite to a tense the source is already in, invent an
/// unrelated tense shift (past+past → present; present+present →
/// future). Two prompt-side attempts to fix this were rolled back —
/// the right fix is upstream, at the UI.
///
/// The contract is intentionally narrow:
/// - Pure function: `(String) -> SelectionTense`.
/// - Output is one of `.past`, `.present`, `.unknown`. Never throws.
/// - Quoted dialogue is excluded so the narrative voice dominates,
///   matching how a human reader would name the tense of the prose.
/// - When the signal is weak or split, return `.unknown` rather than
///   guess — the wiring then opens both menu entries and falls back
///   to a "could not detect source tense, sending as-is" tray note
///   on click.
func phase4SelectionTenseHeuristicTests() -> TestSuite {
    let s = TestSuite("Phase4SelectionTenseHeuristic")

    // MARK: - Trivial inputs

    s.test("empty string is .unknown") {
        try expectEqual(SelectionTenseHeuristic.classify(""), .unknown)
    }

    s.test("whitespace-only input is .unknown") {
        try expectEqual(SelectionTenseHeuristic.classify("   \n\t  "), .unknown)
    }

    s.test("no verbs at all is .unknown") {
        try expectEqual(SelectionTenseHeuristic.classify("Hello! Yes. No, never."), .unknown)
    }

    s.test("single ambiguous verb is .unknown (not enough signal)") {
        // "read" is past/present-tense ambiguous in surface form; one
        // verb on its own should never carry the verdict.
        try expectEqual(SelectionTenseHeuristic.classify("She read."), .unknown)
    }

    // MARK: - Clear past-tense narrative

    s.test("clear past-tense narrative classifies as .past") {
        let text = """
        She walked to the door and turned the handle. The hallway was empty.
        Daniel had been waiting for her in the kitchen, his coffee already cold.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .past)
    }

    s.test("past-tense with irregular forms (was/were/had/took) classifies as .past") {
        let text = """
        Iris took the glass from him. The room felt colder than it had any right to.
        Her shoulders were tight; she leaned against the counter.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .past)
    }

    s.test("past perfect ('had been working') classifies as .past") {
        let text = """
        He had been working at the dossier for hours. The lamp had grown hot.
        Outside, the street had emptied.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .past)
    }

    // MARK: - Clear present-tense narrative

    s.test("clear present-tense narrative classifies as .present") {
        let text = """
        She walks to the door and turns the handle. The hallway is empty.
        Daniel is waiting for her in the kitchen, his coffee already cold.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .present)
    }

    s.test("present continuous ('is walking', 'are sitting') classifies as .present") {
        let text = """
        Iris is standing by the window. Daniel is watching her from the doorway.
        They are not speaking. The kettle is whistling, ignored.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .present)
    }

    // MARK: - Dialogue exclusion

    s.test("past narrative with quoted present-tense dialogue still classifies as .past") {
        let text = """
        "I am tired," she said. "I do not want to go." She had been awake for hours,
        and the room had grown cold around her. He nodded and turned away.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .past)
    }

    s.test("present narrative with quoted past-tense dialogue still classifies as .present") {
        let text = """
        "I walked all the way here," he says. "It took an hour." She watches him
        from the chair. The fire is low. She is not impressed.
        """
        try expectEqual(SelectionTenseHeuristic.classify(text), .present)
    }

    // MARK: - Split / mixed signal

    s.test("near-50/50 split returns .unknown rather than guess") {
        // Two verbs of each tense, no clear majority — the heuristic
        // should abstain so the wiring opens both menu entries.
        try expectEqual(SelectionTenseHeuristic.classify("She walked. He walks. She turned. He turns."), .unknown)
    }

    return s
}
