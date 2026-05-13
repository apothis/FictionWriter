import Foundation

/// Phase 7.b.5 — JSON contract for JS→Swift partial updates to a
/// `TemplateScene`. Mirrors `ReferencePatch` semantics: every field
/// is `Optional`; the React side sends only diverging fields. `nil`
/// means "leave alone"; a present value sets exactly.
///
/// Patchable surface is the user-editable fields only: `name`,
/// `nsfw`, `body`. `id` is carried at the intent envelope; `createdAt`
/// and `extraFrontmatter` are not patchable from the workspace.
public struct TemplateScenePatch: Codable, Equatable {
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

    public func apply(to scene: TemplateScene) -> TemplateScene {
        var s = scene
        if let v = name { s.name = v }
        if let v = nsfw { s.nsfw = v }
        if let v = body { s.body = v }
        return s
    }
}
