import Foundation

/// Manuscript hierarchy. Phase 1 ships only `orphanedSceneIds` populated;
/// `partIds` is the Phase 3+ Parts/Chapters extension hook (declared now
/// so existing on-disk Project files don't need a non-additive bump when
/// 1.3 lands).
public struct Manuscript: Codable, Equatable {
    public var partIds: [UUID]
    public var orphanedSceneIds: [UUID]

    public init(partIds: [UUID] = [], orphanedSceneIds: [UUID] = []) {
        self.partIds = partIds
        self.orphanedSceneIds = orphanedSceneIds
    }

    public static let empty = Manuscript()
}
