import Foundation

/// Continuity Audit (L10) — Phase B, subject resolution (pure data).
///
/// A claim's `subject` is whatever surface form the LLM wrote — "Mara",
/// "Mara Vance", "she". Conflict retrieval groups claims by subject, so
/// an ungrounded subject fragments one entity across several groups and
/// silently loses real conflicts. This step rewrites each claim's
/// subject to a canonical, human-readable entity name.
///
/// Matching is exact (normalised) against an entity's name and aliases
/// — the deterministic, no-false-positive core. Pronoun / coreference
/// resolution is out of scope (an unresolved subject simply falls back
/// to its normalised surface form); richer grounding via `GLiNERDetector`
/// is an engine-level concern layered on top — see
/// `LOOM_CONTINUITY_AUDIT.md` §3.1.
public enum ContinuitySubjectResolver {

    /// A bible entity (or GLiNER-detected entity) to resolve against.
    public struct KnownEntity: Equatable {
        public let name: String
        public let aliases: [String]

        public init(name: String, aliases: [String]) {
            self.name = name
            self.aliases = aliases
        }
    }

    /// Resolve a free-text subject to a canonical entity name. Returns
    /// the entity's `name` when the subject normalises to that name or
    /// any of its aliases; otherwise the normalised surface string.
    public static func resolve(subject: String, entities: [KnownEntity]) -> String {
        let needle = ContinuityConflictRetrieval.normalize(subject)
        for entity in entities {
            var forms = [entity.name]
            forms.append(contentsOf: entity.aliases)
            if forms.contains(where: { ContinuityConflictRetrieval.normalize($0) == needle }) {
                return entity.name
            }
        }
        return needle
    }

    /// Rewrite every claim's `subject` to its resolved canonical form.
    public static func ground(
        claims: [ContinuityAudit.Claim],
        entities: [KnownEntity]
    ) -> [ContinuityAudit.Claim] {
        claims.map { claim in
            var grounded = claim
            grounded.subject = resolve(subject: claim.subject, entities: entities)
            return grounded
        }
    }
}
