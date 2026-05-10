import Foundation

/// Append-only debug log written to `$TMPDIR/loom-debug.log`.
/// Tail with: `tail -f $TMPDIR/loom-debug.log`.
///
/// Loom uses `[subsystem] event: data` line shapes from day one, per the
/// inherited diagnostic-logging posture: `[loom]` for app lifecycle,
/// `[project]`, `[editor]`, `[bible]`, `[gen]`, `[storage]` for the
/// per-domain subsystems landing across sub-steps 1.b–1.k. Lines are
/// grep-able from the moment a feature ships — `[gen]` should never appear
/// before sub-step 1.i, `[bible]` not before 1.g, etc.
public final class DebugLog {
    public static let shared = DebugLog()
    private let url: URL
    private let queue = DispatchQueue(label: "Loom.DebugLog")
    private let formatter: DateFormatter

    private init() {
        let tmp = FileManager.default.temporaryDirectory
        url = tmp.appendingPathComponent("loom-debug.log")
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        try? "\n=== launched \(Date()) ===\n".write(to: url, atomically: true, encoding: .utf8)
    }

    public func write(_ s: String) {
        queue.async {
            let line = "[\(self.formatter.string(from: Date()))] \(s)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: self.url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        }
    }

    public var path: String { url.path }
}
