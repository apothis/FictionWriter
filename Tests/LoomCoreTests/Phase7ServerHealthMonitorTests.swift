import Foundation
@testable import LoomCore

/// Phase 7 followup — periodic server health probe with edge-only
/// log transitions. RPClient already does this; Loom previously had
/// only a single-shot probe at launch + on session URL change, so a
/// server drop / reconnect during a session was invisible until the
/// user tried to generate.
///
/// The pure-data piece is the transition-message helper: given the
/// previously-observed status and a fresh probe outcome, return a
/// log line iff the reachable/unreachable axis changed. Repeated
/// successful probes return nil (no log spam from the 30s tick).
func phase7ServerHealthMonitorTests() -> TestSuite {
    let s = TestSuite("Phase7ServerHealthMonitor")

    s.test("transitionMessage emits initial-reachable line on first observation") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: nil,
            to: .reachable(model: "gemma-31B", maxContext: 16384)
        )
        try expectTrue(msg != nil, "expected non-nil log line")
        try expectTrue(msg?.contains("gemma-31B") == true,
            "expected model name in log line; got \(msg ?? "nil")")
    }

    s.test("transitionMessage emits unreachable line on first observation") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: nil,
            to: .unreachable
        )
        try expectTrue(msg != nil, "expected non-nil log line")
        try expectTrue(msg?.lowercased().contains("unreachable") == true,
            "got \(msg ?? "nil")")
    }

    s.test("transitionMessage suppresses repeated reachable probes (no log spam)") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: .reachable(model: "gemma-31B", maxContext: 16384),
            to: .reachable(model: "gemma-31B", maxContext: 16384)
        )
        try expectTrue(msg == nil)
    }

    s.test("transitionMessage suppresses repeated unreachable probes") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: .unreachable, to: .unreachable
        )
        try expectTrue(msg == nil)
    }

    s.test("transitionMessage flags reachable → unreachable as a drop") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: .reachable(model: "gemma-31B", maxContext: 16384),
            to: .unreachable
        )
        try expectTrue(msg != nil, "expected non-nil log line")
        try expectTrue(msg?.lowercased().contains("unreachable") == true
                    || msg?.lowercased().contains("lost") == true
                    || msg?.lowercased().contains("dropped") == true,
            "expected a 'lost/dropped/unreachable' marker; got \(msg ?? "nil")")
    }

    s.test("transitionMessage flags unreachable → reachable as a reconnect") {
        let msg = ServerHealthMonitor.transitionMessage(
            from: .unreachable,
            to: .reachable(model: "gemma-31B", maxContext: 16384)
        )
        try expectTrue(msg != nil, "expected non-nil log line")
        // The recovery line should be distinguishable from the
        // initial-reachable line (different lifecycle event).
        try expectTrue(msg?.lowercased().contains("back") == true
                    || msg?.lowercased().contains("reconnect") == true
                    || msg?.lowercased().contains("recover") == true,
            "expected a 'back online / reconnected' marker; got \(msg ?? "nil")")
    }

    s.test("transitionMessage suppresses repeated reachable probes even when only the model name changes") {
        // A model swap is interesting but not a connection-health
        // event. The existing probe-success logging captures model
        // changes; this helper is strictly about the up/down axis.
        let msg = ServerHealthMonitor.transitionMessage(
            from: .reachable(model: "gemma-31B", maxContext: 16384),
            to: .reachable(model: "qwen-72B", maxContext: 32768)
        )
        try expectTrue(msg == nil)
    }

    // MARK: - Initial-probe retry gate
    //
    // macOS Local Network privacy (TCC) can block the very first
    // request after launch for 1–3s while the grant settles. The
    // launch probe lost that race repeatedly — showed "unreachable"
    // for 30s until the next periodic tick caught the recovery.
    // Fix: stay in .unknown for a short retry burst on initial
    // failure, only post .unreachable after the burst exhausts.

    s.test("shouldRetryInitialProbe true when no prior observation and budget remains") {
        try expectTrue(ServerHealthMonitor.shouldRetryInitialProbe(
            lastObserved: nil, retriesRemaining: 3
        ))
    }

    s.test("shouldRetryInitialProbe true when prior is .unknown and budget remains") {
        try expectTrue(ServerHealthMonitor.shouldRetryInitialProbe(
            lastObserved: .unknown, retriesRemaining: 1
        ))
    }

    s.test("shouldRetryInitialProbe false when budget is exhausted") {
        try expectFalse(ServerHealthMonitor.shouldRetryInitialProbe(
            lastObserved: nil, retriesRemaining: 0
        ))
    }

    s.test("shouldRetryInitialProbe false once we've posted .unreachable") {
        // After the retry burst exhausts and we commit to unreachable,
        // a later tick failure must not enter another retry loop —
        // it's a real outage at that point.
        try expectFalse(ServerHealthMonitor.shouldRetryInitialProbe(
            lastObserved: .unreachable, retriesRemaining: 3
        ))
    }

    s.test("shouldRetryInitialProbe false once we've seen a success") {
        // A real drop after a successful observation is a transition,
        // not a TCC race — post it immediately.
        try expectFalse(ServerHealthMonitor.shouldRetryInitialProbe(
            lastObserved: .reachable(model: "gemma-31B", maxContext: 16384),
            retriesRemaining: 3
        ))
    }

    s.test("transitionMessage treats .unknown as no prior observation") {
        // .unknown is the bootstrap state shown by StatusStripView
        // before the first probe lands. Same treatment as nil.
        let toReachable = ServerHealthMonitor.transitionMessage(
            from: .unknown,
            to: .reachable(model: "gemma-31B", maxContext: 16384)
        )
        try expectTrue(toReachable != nil)
        let toUnreachable = ServerHealthMonitor.transitionMessage(
            from: .unknown,
            to: .unreachable
        )
        try expectTrue(toUnreachable != nil)
    }

    return s
}
