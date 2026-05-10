import Foundation

/// Manuscript hierarchy. Phase 1 ships only `orphanedSceneIds` populated;
/// `partIds` is the Phase 3+ Parts/Chapters extension hook (declared now
/// so existing on-disk Project files don't need a non-additive bump when
/// 1.3 lands).
///
/// `trashedSceneIds` carries scenes the user has deleted via the sidebar.
/// Per LOOM_DESIGN_LANGUAGE.md §14.3 Trash "survives close, emptied
/// explicitly" — Phase 1 keeps deleted scenes around so undelete is
/// cheap; Phase 6 polish may add an "empty trash" affordance.
public struct Manuscript: Codable, Equatable {
    public var partIds: [UUID]
    public var orphanedSceneIds: [UUID]
    public var trashedSceneIds: [UUID]

    public init(
        partIds: [UUID] = [],
        orphanedSceneIds: [UUID] = [],
        trashedSceneIds: [UUID] = []
    ) {
        self.partIds = partIds
        self.orphanedSceneIds = orphanedSceneIds
        self.trashedSceneIds = trashedSceneIds
    }

    public static let empty = Manuscript()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.partIds = try c.decodeIfPresent([UUID].self, forKey: .partIds) ?? []
        self.orphanedSceneIds = try c.decodeIfPresent([UUID].self, forKey: .orphanedSceneIds) ?? []
        self.trashedSceneIds = try c.decodeIfPresent([UUID].self, forKey: .trashedSceneIds) ?? []
    }
}
