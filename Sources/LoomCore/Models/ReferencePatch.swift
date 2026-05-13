import Foundation

/// Phase 5 production A2.1 — JSON contract for JS→Swift partial
/// updates to a `ReferenceText`. Mirrors `CharacterPatch` /
/// `LorebookEntryPatch` semantics: every field is `Optional`; the
/// React side sends only diverging fields. `nil` means "leave alone";
/// a present value sets exactly.
///
/// Patchable surface is the user-editable fields only:
/// `name`, `nsfw`, `body`. `id` is carried at the intent envelope
/// level; `createdAt` and `extraFrontmatter` are not patchable from
/// the React side (creation time is fixed, and the frontmatter
/// passthrough is for future import-tool round-tripping that doesn't
/// route through the Bible Workspace).
public struct ReferencePatch: Codable, Equatable {
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

    public func apply(to ref: ReferenceText) -> ReferenceText {
        var r = ref
        if let v = name { r.name = v }
        if let v = nsfw { r.nsfw = v }
        if let v = body { r.body = v }
        return r
    }
}
