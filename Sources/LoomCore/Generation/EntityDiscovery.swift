import Foundation

/// Phase 9 entity-discovery — pure-data types.
///
/// LOOM_ENTITY_DISCOVERY_SPIKE §3.2: shapes for the six-stage pipeline
/// that extends Pass-B (LedgerExtraction) to *discover* new characters
/// and places in scene prose, attach facts, and surface them in the
/// Bible Workspace webview as accept/reject/edit suggestions.
///
/// Sibling namespace to `LedgerExtraction`. Shapes are designed so
/// `ExtractedFact.characterId` can reference either a real
/// `Character.id` (existing bible row) or a `ProposedEntity.id`
/// (not yet promoted) — same string-typed field, no schema break.
public enum EntityDiscovery {

    // MARK: - Types

    public enum Kind: String, Codable, Equatable, CaseIterable {
        case character
        case place
    }

    /// A discovered entity that has cleared the promotion gate (§3.1
    /// Stage B) and dedup (§3.1 Stage C) but has not yet been accepted
    /// by the user. Promoted to a real `Character` / `Setting` on
    /// `acceptEntityProposal` bridge intent.
    public struct ProposedEntity: Codable, Equatable {
        public let id: UUID
        public let kind: Kind
        public let canonicalName: String
        public let aliases: [String]
        public let oneLine: String
        public let evidenceQuote: String
        public let sourceSceneId: UUID
        /// 0…1 gate output. Clamped at construction so a buggy LLM
        /// emit can never crash the pipeline downstream.
        public let confidence: Double

        public init(
            id: UUID,
            kind: Kind,
            canonicalName: String,
            aliases: [String],
            oneLine: String,
            evidenceQuote: String,
            sourceSceneId: UUID,
            confidence: Double
        ) {
            self.id = id
            self.kind = kind
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.oneLine = oneLine
            self.evidenceQuote = evidenceQuote
            self.sourceSceneId = sourceSceneId
            self.confidence = max(0.0, min(1.0, confidence))
        }
    }

    /// Bundle of facts attached to one proposed entity. On accept,
    /// facts flow into the bible alongside the promoted entity in a
    /// single atomic operation (Phase 4 fact-merge semantics apply
    /// per existing `LedgerSuggestionAcceptor`).
    public struct ProposedEntityFacts: Codable, Equatable {
        public let proposedEntityId: UUID
        public let facts: [LedgerExtraction.ExtractedFact]

        public init(proposedEntityId: UUID, facts: [LedgerExtraction.ExtractedFact]) {
            self.proposedEntityId = proposedEntityId
            self.facts = facts
        }
    }

    // MARK: - Stage B: anatomy-descriptor block-list (§4.6)

    /// Anatomy descriptors that, when they ARE the whole canonical
    /// name (modulo a generic noun + leading determiner), should
    /// block promotion. NSFW prose identifies otherwise-unnamed
    /// characters by hair/skin/build features; promoting these as
    /// distinct characters duplicates ones the user already has
    /// permanent names for. Kept narrow on purpose: only add a root
    /// here once the live spike surfaces a recurring false-positive.
    static let anatomyDescriptorRoots: Set<String> = [
        "redhead", "redheads", "redheaded",
        "brunette", "brunettes",
        "blonde", "blond", "blondes", "blonds",
    ]

    /// Generic nouns that anatomy descriptors typically modify
    /// ("the brunette woman", "the blonde girl"). When a phrase is
    /// wholly `{anatomy} + {generic}` modulo determiner, it's still
    /// anatomy-only and gets rejected.
    static let genericPersonNouns: Set<String> = [
        "woman", "women", "girl", "girls",
        "man", "men", "boy", "boys",
        "lady", "ladies", "person", "people",
    ]

    static let leadingDeterminers: Set<String> = ["the", "a", "an"]

    /// Returns true iff the given canonical-name candidate is
    /// *wholly* an anatomy-descriptor phrase (i.e. anatomy root,
    /// optionally with leading determiner + trailing generic noun).
    /// Any other content word — proper noun, occupation, location
    /// modifier — flips the answer to false so the entity is kept.
    public static func isAnatomyOnlyDescriptor(_ candidate: String) -> Bool {
        var words = candidate
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
        // Strip a single leading determiner if present.
        if let first = words.first, leadingDeterminers.contains(first) {
            words.removeFirst()
        }
        guard !words.isEmpty else { return false }
        // Every remaining word must be anatomy or a generic person
        // noun. A single unknown word (proper noun, role, "captain")
        // disqualifies the reject.
        var sawAnatomy = false
        for w in words {
            if anatomyDescriptorRoots.contains(w) {
                sawAnatomy = true
            } else if genericPersonNouns.contains(w) {
                // generic alone isn't anatomy-only, but generic
                // alongside anatomy is — track and check at end.
                continue
            } else {
                return false
            }
        }
        return sawAnatomy
    }
}
