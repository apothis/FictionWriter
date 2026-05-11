import Foundation
@testable import LoomCore

/// Phase 2 follow-on (HANDOFF §9.2) — auto-probe on server add.
/// The ServerProbe.probe call requires a live endpoint and can't be
/// unit-tested; this suite pins the *pure* "apply probe result to
/// settings" helper that the add-server path calls when the probe
/// returns. The fire-the-probe async wiring in ServersTabVC is
/// honest UI (verified by running the app).
func phase2AutoProbeTests() -> TestSuite {
    let s = TestSuite("Phase2AutoProbe")

    s.test("applyProbeResult writes capabilities + lastProbed onto the profile") {
        var settings = AppSettings.defaults
        let profile = ServerProfile(name: "Live", baseURL: URL(string: "http://192.168.1.201:5001")!)
        settings.addServer(profile)

        let caps = ServerCapabilities(modelName: "Qwen3.6-27B", trueMaxContext: 32768, version: "1.85.1")
        let stamp = Date(timeIntervalSince1970: 1_710_000_000)

        let updated = AutoProbe.applyResult(caps, lastProbed: stamp, to: profile.id, in: settings)
        let updatedProfile = try expectNotNil(updated.servers.first { $0.id == profile.id })
        try expectEqual(updatedProfile.capabilities, caps)
        try expectEqual(updatedProfile.lastProbed, stamp)
    }

    s.test("applyResult on an unknown profileId leaves settings unchanged") {
        var settings = AppSettings.defaults
        settings.addServer(ServerProfile(name: "A", baseURL: URL(string: "http://a")!))
        let stranger = UUID()
        let caps = ServerCapabilities(modelName: "M", trueMaxContext: 8192, version: "1.0")
        let after = AutoProbe.applyResult(caps, lastProbed: Date(), to: stranger, in: settings)
        try expectEqual(after, settings)
    }

    return s
}
