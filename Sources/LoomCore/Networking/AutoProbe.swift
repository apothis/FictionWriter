import Foundation

/// Phase 2 follow-on (HANDOFF §9.2) — apply a `ServerProbe` result to
/// an `AppSettings` snapshot. Pure projection so the async-fire path
/// in `ServersTabViewController` stays minimal: kick off the probe,
/// when the callback lands route through this helper, then
/// `appState.updateSettings(_:)`.
public enum AutoProbe {
    /// Returns a new `AppSettings` with the target profile's
    /// `capabilities` + `lastProbed` updated. If `profileId` doesn't
    /// match any server in the snapshot, returns the input unchanged
    /// — a stale callback after the user deleted the profile must
    /// not resurrect it.
    public static func applyResult(
        _ capabilities: ServerCapabilities,
        lastProbed: Date,
        to profileId: UUID,
        in settings: AppSettings
    ) -> AppSettings {
        var out = settings
        guard let idx = out.servers.firstIndex(where: { $0.id == profileId }) else {
            return settings
        }
        out.servers[idx].capabilities = capabilities
        out.servers[idx].lastProbed = lastProbed
        return out
    }
}
