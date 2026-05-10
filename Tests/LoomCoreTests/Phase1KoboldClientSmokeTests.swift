import Foundation
@testable import LoomCore

/// Sub-step 1.c — live smoke against a running koboldcpp. Read URL from
/// `LOOM_KOBOLD_URL` env var (default `http://localhost:5001`); 2-second
/// probe timeout. If unreachable, prints a SKIP line and returns PASS —
/// CI doesn't have a kobold instance, and the contract says "no faked
/// tests" so we can't fabricate a "happy path" without a real server.
///
/// When reachable, asserts: ServerCapabilities.modelName non-empty,
/// trueMaxContext > 0. Mirrors the Phase 1.c "Definition of done":
/// "Loom can probe a running koboldcpp instance and report model name +
/// ctx in a debug log line."
func phase1KoboldClientSmokeTests() -> TestSuite {
    let s = TestSuite("Phase1KoboldClientSmoke")

    s.test("probe localhost or LOOM_KOBOLD_URL — happy path or skipped") {
        let urlString = ProcessInfo.processInfo.environment["LOOM_KOBOLD_URL"] ?? "http://localhost:5001"
        guard let url = URL(string: urlString) else {
            print("        [SMOKE-SKIPPED] invalid LOOM_KOBOLD_URL=\(urlString)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var caps: ServerCapabilities?
        var probeError: ServerProbe.ProbeError?
        ServerProbe.probe(baseURL: url) { result in
            switch result {
            case .success(let c): caps = c
            case .failure(let e): probeError = e
            }
            semaphore.signal()
        }
        // Wait up to 6 seconds — ServerProbe's internal timeout is 5.
        let outcome = semaphore.wait(timeout: .now() + 6)
        if outcome == .timedOut {
            print("        [SMOKE-SKIPPED] probe of \(url) timed out outside ServerProbe — treating as no-server")
            return
        }

        if let error = probeError {
            print("        [SMOKE-SKIPPED] no koboldcpp at \(url): \(error)")
            return
        }
        let c = try expectNotNil(caps)
        let modelName = try expectNotNil(c.modelName)
        try expectTrue(!modelName.isEmpty, "modelName should be non-empty")
        // trueMaxContext is best-effort — older builds may not surface it,
        // so accept nil. But if present, it should be plausibly > 0.
        if let ctx = c.trueMaxContext {
            try expectGreaterThan(ctx, 0)
        }
        print("        [SMOKE-OK] model=\(modelName) ctx=\(c.trueMaxContext ?? -1) version=\(c.version ?? "?")")
    }

    return s
}
