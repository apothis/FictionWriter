import Foundation
@testable import LoomCore

/// Sub-step 1.j.B — pure state machine governing what happens to a
/// freshly-streamed AI insertion. Two states (idle / awaiting), four
/// user transitions (accept / reject / redo / implicit-accept), one
/// system transition (generationFinished). Side effects are returned
/// as `Action` values; the editor performs them.
func phase1AcceptanceStateTests() -> TestSuite {
    let s = TestSuite("Phase1AcceptanceState")

    s.test("default state is idle") {
        let machine = AcceptanceMachine()
        try expectEqual(machine.state, .idle)
    }

    s.test("generationFinished transitions to awaiting") {
        var machine = AcceptanceMachine()
        let range = NSRange(location: 10, length: 50)
        machine.handleGenerationFinished(insertedRange: range, mode: .continueProse)
        try expectEqual(machine.state, .awaiting(insertedRange: range, mode: .continueProse))
    }

    s.test("accept while awaiting returns to idle, no text mutation") {
        var machine = AcceptanceMachine()
        machine.handleGenerationFinished(insertedRange: NSRange(location: 0, length: 5), mode: .continueProse)
        let action = machine.handleAccept()
        try expectEqual(machine.state, .idle)
        try expectEqual(action, .nothing)
    }

    s.test("reject while awaiting returns to idle and requests range removal") {
        var machine = AcceptanceMachine()
        let range = NSRange(location: 10, length: 50)
        machine.handleGenerationFinished(insertedRange: range, mode: .continueProse)
        let action = machine.handleReject()
        try expectEqual(machine.state, .idle)
        try expectEqual(action, .removeText(range))
    }

    s.test("redo while awaiting returns to idle, requests removeAndRestart") {
        var machine = AcceptanceMachine()
        let range = NSRange(location: 10, length: 50)
        machine.handleGenerationFinished(insertedRange: range, mode: .expand)
        let action = machine.handleRedo()
        try expectEqual(machine.state, .idle)
        try expectEqual(action, .removeAndRestart(range, .expand))
    }

    s.test("implicit accept (typing into block) returns to idle") {
        var machine = AcceptanceMachine()
        machine.handleGenerationFinished(insertedRange: NSRange(location: 0, length: 5), mode: .continueProse)
        let action = machine.handleImplicitAccept()
        try expectEqual(machine.state, .idle)
        try expectEqual(action, .nothing)
    }

    s.test("transitions while idle are no-ops") {
        var machine = AcceptanceMachine()
        try expectEqual(machine.handleAccept(), .nothing)
        try expectEqual(machine.handleReject(), .nothing)
        try expectEqual(machine.handleRedo(), .nothing)
        try expectEqual(machine.handleImplicitAccept(), .nothing)
        try expectEqual(machine.state, .idle)
    }

    s.test("generationFinished while awaiting replaces previous awaiting") {
        // E.g. redo path that re-fires generationFinished without an
        // intervening accept/reject.
        var machine = AcceptanceMachine()
        machine.handleGenerationFinished(insertedRange: NSRange(location: 0, length: 5), mode: .continueProse)
        machine.handleGenerationFinished(insertedRange: NSRange(location: 10, length: 8), mode: .continueProse)
        try expectEqual(
            machine.state,
            .awaiting(insertedRange: NSRange(location: 10, length: 8), mode: .continueProse)
        )
    }

    return s
}
