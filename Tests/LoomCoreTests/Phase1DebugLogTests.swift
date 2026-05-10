import Foundation
@testable import LoomCore

/// Sub-step 1.a — DebugLog port verification. Mirrors RPClient's debug log
/// pattern: append-only file under $TMPDIR, timestamped lines, the `path`
/// property exposed for `tail -f` instructions in the README.
///
/// The behaviour we care about in 1.a:
///  - The log file lives at `$TMPDIR/loom-debug.log` (renamed from
///    `rpclient-debug.log`; verifies the namespace adjust took).
///  - `write(_:)` actually appends a line containing the given payload.
///  - The class is `public` so AppDelegate (LoomCore) AND any future
///    same-module callers can reach it without re-architecture.
///
/// Writes happen on a background queue, so the test sleeps briefly to let
/// the queue drain before reading. A short `Thread.sleep` is the simplest
/// thing that works; if it ever flakes we can swap in a barrier.
func phase1DebugLogTests() -> TestSuite {
    let s = TestSuite("Phase1DebugLog")

    s.test("path lives at $TMPDIR/loom-debug.log") {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-debug.log")
            .path
        try expectEqual(DebugLog.shared.path, expected)
    }

    s.test("write appends a line containing the payload") {
        let marker = "loom-debuglog-test-\(UUID().uuidString)"
        DebugLog.shared.write("[loom] \(marker)")

        // Drain the dispatch queue. Two short sleeps catch slow CI; a
        // single 100ms sleep is plenty in practice.
        Thread.sleep(forTimeInterval: 0.1)

        let url = URL(fileURLWithPath: DebugLog.shared.path)
        let contents = try String(contentsOf: url, encoding: .utf8)
        try expectTrue(contents.contains(marker), "log file should contain marker after write")
    }

    return s
}
