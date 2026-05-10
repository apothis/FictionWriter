import Foundation

/// Pure state machine for the post-generation acceptance window.
///
/// Two persistent states:
///   - `.idle` — no AI insertion awaiting a decision
///   - `.awaiting(insertedRange, mode)` — there's a recently-generated
///     block of prose at `insertedRange`, the user must accept / reject /
///     redo / type-into-it before further generations should fire.
///
/// All user-facing transitions return an `Action` describing what side
/// effect the consumer (EditorViewController) should perform. The state
/// machine itself never touches text; that's the editor's job.
public struct AcceptanceMachine: Equatable {
    public enum State: Equatable {
        case idle
        case awaiting(insertedRange: NSRange, mode: GenerationMode)
    }

    public enum Action: Equatable {
        /// Caller does nothing further (state already reflects the outcome).
        case nothing
        /// Caller deletes the given range from the text storage.
        case removeText(NSRange)
        /// Caller deletes the given range AND fires a fresh generation
        /// of the same mode (Keep & Redo / re-roll).
        case removeAndRestart(NSRange, GenerationMode)
    }

    public private(set) var state: State = .idle

    public init() {}

    /// Stream finished — there's now an inserted block awaiting a
    /// user decision. Replaces any prior `.awaiting` state (the redo
    /// path can chain `generationFinished` after a previous one
    /// without an intervening accept/reject).
    public mutating func handleGenerationFinished(insertedRange: NSRange, mode: GenerationMode) {
        state = .awaiting(insertedRange: insertedRange, mode: mode)
    }

    public mutating func handleAccept() -> Action {
        guard case .awaiting = state else { return .nothing }
        state = .idle
        return .nothing
    }

    public mutating func handleReject() -> Action {
        guard case .awaiting(let range, _) = state else { return .nothing }
        state = .idle
        return .removeText(range)
    }

    public mutating func handleRedo() -> Action {
        guard case .awaiting(let range, let mode) = state else { return .nothing }
        state = .idle
        return .removeAndRestart(range, mode)
    }

    /// User typed into the inserted block before deciding. Per the
    /// Cursor / GitHub Copilot ghost-text convention this is treated
    /// as Accept.
    public mutating func handleImplicitAccept() -> Action {
        guard case .awaiting = state else { return .nothing }
        state = .idle
        return .nothing
    }
}
