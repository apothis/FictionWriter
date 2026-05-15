import Foundation

/// Phase 9 entity-discovery — Stage B promotion gate.
///
/// Pure-data filter applied after candidate generation, before dedup
/// + LLM normalisation. v1 posture (per LOOM_ENTITY_DISCOVERY_SPIKE
/// §4.3): proper-noun-only proposals. Definite-NP entities ("the
/// cook", "the woman in red") deferred to v2 — they need cross-scene
/// coreference + recurrence to gate safely, and v1 doesn't have
/// either.
///
/// Filter order:
///   1. Empty / whitespace / determiner-only → `.rejectEmpty`
///   2. Anatomy block-list (§4.6) → `.rejectAnatomyOnly`
///   3. At least one capitalised non-determiner token → `.promote`
///   4. Else → `.rejectNoProperNoun`
///
/// The gate is intentionally conservative: false-negative on a rare
/// intentional anatomy-stage-name beats false-positive on every
/// anatomy descriptor in NSFW prose.
public enum EntityPromotionGate {

    public enum Verdict: Equatable {
        case promote
        case rejectAnatomyOnly
        case rejectNoProperNoun
        case rejectEmpty
    }

    public static func evaluate(canonicalName: String) -> Verdict {
        let trimmed = canonicalName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .rejectEmpty }

        // After stripping leading determiner, is anything left?
        var tokens = trimmed.split(separator: " ").map(String.init)
        if let first = tokens.first?.lowercased(),
           EntityDiscovery.leadingDeterminers.contains(first) {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { return .rejectEmpty }

        // Anatomy block-list wins over proper-noun check — see
        // §4.6 + test "anatomy gate wins over proper-noun gate on
        // collision".
        if EntityDiscovery.isAnatomyOnlyDescriptor(trimmed) {
            return .rejectAnatomyOnly
        }

        // Proper-noun heuristic: at least one token starts with an
        // uppercase letter. The leading determiner has already been
        // stripped above so a sentence-initial "The" doesn't count
        // unless it survives the strip (e.g. proper-noun place name
        // "The Quay" → "Quay" remains, which IS capitalised).
        for token in tokens {
            if let first = token.unicodeScalars.first,
               CharacterSet.uppercaseLetters.contains(first) {
                return .promote
            }
        }
        return .rejectNoProperNoun
    }
}
