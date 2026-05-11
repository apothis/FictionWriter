import Foundation

/// Phase 2 #10 — inline entity reference in prose. On-disk grammar
/// `[<displayName>](#entity/<uuid>)` survives any markdown editor's
/// round-trip; in the Loom editor the link colour matches body text
/// (labelColor, not system blue) so it reads as plain prose
/// (LOOM_DESIGN_LANGUAGE.md §14.5.1).
///
/// The `category` field is what the resolver fills in at render-time
/// by looking up the id in the Project — parsing alone returns an
/// "unresolved" reference where `category == nil`.
public struct EntityReference: Equatable {
    public let id: UUID
    public let displayName: String
    /// Optional because the parse stage doesn't have a Project to
    /// resolve the id's category against. Mention-sparkline (#11)
    /// fills this in post-parse.
    public var category: BibleCategory?

    public init(category: BibleCategory?, id: UUID, displayName: String) {
        self.category = category
        self.id = id
        self.displayName = displayName
    }

    /// Markdown encoding: `[<displayName>](#entity/<uuid>)`. UUID is
    /// lowercased to match the standard textual form on disk.
    public var markdown: String {
        "[\(displayName)](#entity/\(id.uuidString.lowercased()))"
    }

    /// Parse a single markdown link into an EntityReference.
    /// Returns nil if the link's URL is not the `#entity/<uuid>` form.
    public static func parse(_ markdown: String) -> EntityReference? {
        guard let match = referencePattern.firstMatch(
            in: markdown,
            options: [],
            range: NSRange(markdown.startIndex..., in: markdown)
        ) else { return nil }
        return reference(from: match, in: markdown)
    }

    /// Scan a prose body and return every entity reference it carries,
    /// in document order. Plain markdown links to URLs / other targets
    /// are skipped — only `#entity/<uuid>` matches.
    public static func scan(in prose: String) -> [EntityReference] {
        scanWithRanges(in: prose).map(\.reference)
    }

    /// One entity reference along with the NSRange it occupies in
    /// the source prose. Used by the hover-preview popover to map
    /// mouse positions back to entity ids.
    public struct Located: Equatable {
        public let reference: EntityReference
        public let range: NSRange
    }

    /// Like `scan(in:)` but also reports each match's NSRange.
    public static func scanWithRanges(in prose: String) -> [Located] {
        let nsRange = NSRange(prose.startIndex..., in: prose)
        let matches = referencePattern.matches(in: prose, options: [], range: nsRange)
        var out: [Located] = []
        for m in matches {
            guard let ref = reference(from: m, in: prose) else { continue }
            out.append(Located(reference: ref, range: m.range))
        }
        return out
    }

    /// Returns the `Located` reference whose range covers
    /// `location`, or nil if the location isn't in any entity link.
    public static func referenceAt(location: Int, in prose: String) -> Located? {
        for hit in scanWithRanges(in: prose) {
            if NSLocationInRange(location, hit.range) { return hit }
        }
        return nil
    }

    // MARK: Internals

    /// `[<display>](#entity/<uuid>)`. Two capture groups: display,
    /// uuid. The pattern intentionally requires the `#entity/` prefix
    /// so ordinary markdown links (`[Link](https://...)`) miss.
    private static let referencePattern: NSRegularExpression = {
        let p = "\\[([^\\]]+)\\]\\(#entity/([0-9A-Fa-f-]+)\\)"
        return try! NSRegularExpression(pattern: p, options: [])
    }()

    private static func reference(from match: NSTextCheckingResult, in body: String) -> EntityReference? {
        guard
            let nameRange = Range(match.range(at: 1), in: body),
            let uuidRange = Range(match.range(at: 2), in: body)
        else { return nil }
        let display = String(body[nameRange])
        let uuidString = String(body[uuidRange])
        guard let id = UUID(uuidString: uuidString) else { return nil }
        return EntityReference(category: nil, id: id, displayName: display)
    }
}
