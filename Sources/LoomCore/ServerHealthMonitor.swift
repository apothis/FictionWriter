import Foundation

/// Phase 7 followup — periodic writer-server health probe with
/// edge-aware log lines.
///
/// Loom's launch-time probe + session-URL-change probe were the
/// only signals on the server-reachable axis; if the writer dropped
/// mid-session the user would only learn at the next generation
/// attempt. RPClient already runs a 30s tick; this is the same idea.
///
/// The pure-data piece is `transitionMessage` — given the
/// last-observed status and a fresh outcome, return a one-line
/// debug-log string iff the up/down axis changed. Repeated probes
/// on the same state return nil so the log doesn't fill with
/// "still reachable" noise at 2/min.
public enum ServerHealthMonitor {

    /// Initial-probe retry budget. macOS Local Network privacy (TCC)
    /// can block the very first network request for 1–3s after launch
    /// while the grant settles into the network stack. The launch
    /// probe loses that race and reports `.unreachable` — a false
    /// negative that shows the user a red dot for 30s until the next
    /// tick catches the recovery.
    ///
    /// During the retry burst, the status stays at `.unknown` (no
    /// red flash). Once the budget exhausts without a success, we
    /// commit to `.unreachable` and the user sees the real outage.
    public static let initialProbeRetryBudget: Int = 4

    /// Delay between retry probes during the launch-time burst.
    /// 1.0s is comfortably longer than the TCC settle window in
    /// practice (~hundreds of ms) and short enough that the user
    /// doesn't perceive a stall.
    public static let initialProbeRetryDelay: TimeInterval = 1.0

    /// Pure-data decision: should the caller retry quietly rather
    /// than post `.unreachable`? True only when no prior observation
    /// has landed AND budget remains. Once any concrete status
    /// (`.reachable` or `.unreachable`) is on file, retries stop —
    /// subsequent failures are real transitions, not TCC races.
    public static func shouldRetryInitialProbe(
        lastObserved: StatusStripView.ServerStatus?,
        retriesRemaining: Int
    ) -> Bool {
        guard retriesRemaining > 0 else { return false }
        switch lastObserved {
        case nil, .unknown: return true
        case .reachable, .unreachable: return false
        }
    }


    /// Returns nil when there is no reachable/unreachable transition
    /// worth logging. Returns a tagged log line otherwise.
    ///
    /// - `old == nil` or `old == .unknown` is "no prior observation"
    ///   and produces an initial-state line.
    /// - A model-name change while staying reachable returns nil:
    ///   the existing `[loom] server probe ok …` line covers that,
    ///   and this helper is strictly about the connection axis.
    public static func transitionMessage(
        from old: StatusStripView.ServerStatus?,
        to new: StatusStripView.ServerStatus
    ) -> String? {
        let oldKind = kind(of: old)
        let newKind = kind(of: new)
        guard oldKind != newKind else { return nil }
        switch newKind {
        case .reachable:
            let model: String? = {
                if case let .reachable(m, _) = new { return m }
                return nil
            }()
            let modelStr = model ?? "?"
            if oldKind == .none {
                return "[health] server reachable: model=\(modelStr)"
            }
            // oldKind == .unreachable
            return "[health] server back online: model=\(modelStr)"
        case .unreachable:
            return "[health] server UNREACHABLE"
        case .none:
            // Transitioning *to* .unknown isn't a real lifecycle event
            // — only the bootstrap state ever sits there. Don't log.
            return nil
        }
    }

    /// Strip the `.reachable` payload so we compare on the axis we
    /// care about. `StatusStripView.ServerStatus`'s `Equatable` is
    /// payload-sensitive (model + maxContext); we deliberately want
    /// model-swap-while-reachable to read as "no transition".
    private enum Kind { case none, reachable, unreachable }
    private static func kind(of status: StatusStripView.ServerStatus?) -> Kind {
        switch status {
        case nil, .unknown: return .none
        case .reachable: return .reachable
        case .unreachable: return .unreachable
        }
    }
}
