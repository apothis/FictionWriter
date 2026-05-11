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
    /// Legacy Phase 1 field — kept for forward-load compatibility
    /// with bundles written before Phase 3. New code reads/writes
    /// `parts` directly. May be removed in a Phase 6 cleanup.
    public var partIds: [UUID]
    /// Phase 3 §A — ordered list of Parts. Phase 3's hierarchical
    /// structure is opt-in; an unstructured project keeps `parts`
    /// empty and all scenes in `orphanedSceneIds`.
    public var parts: [Part]
    public var orphanedSceneIds: [UUID]
    public var trashedSceneIds: [UUID]

    public init(
        partIds: [UUID] = [],
        parts: [Part] = [],
        orphanedSceneIds: [UUID] = [],
        trashedSceneIds: [UUID] = []
    ) {
        self.partIds = partIds
        self.parts = parts
        self.orphanedSceneIds = orphanedSceneIds
        self.trashedSceneIds = trashedSceneIds
    }

    public static let empty = Manuscript()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.partIds = try c.decodeIfPresent([UUID].self, forKey: .partIds) ?? []
        self.parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        self.orphanedSceneIds = try c.decodeIfPresent([UUID].self, forKey: .orphanedSceneIds) ?? []
        self.trashedSceneIds = try c.decodeIfPresent([UUID].self, forKey: .trashedSceneIds) ?? []
    }
}
