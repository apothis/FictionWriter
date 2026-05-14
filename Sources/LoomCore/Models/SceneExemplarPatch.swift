import Foundation

/// Phase 8.b.6 — JSON contract for JS→Swift partial updates to a
/// scene exemplar. Mirrors `ReferencePatch` shape: every field is
/// optional; nil means "leave alone." The handler applies the patch
/// to BOTH the underlying Reference and the Template so the
/// projection stays consistent.
public struct SceneExemplarPatch: Codable, Equatable {
    public var name: String?
    public var nsfw: Bool?
    public var body: String?

    public init(
        name: String? = nil,
        nsfw: Bool? = nil,
        body: String? = nil
    ) {
        self.name = name
        self.nsfw = nsfw
        self.body = body
    }
}
