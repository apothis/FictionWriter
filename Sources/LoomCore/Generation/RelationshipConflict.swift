import Foundation

/// Phase 10 step 4a — detecting when accepting a relationship should
/// prompt "demote the prior one to past?".
///
/// A character normally holds only one *current* romantic-partner
/// edge at a time. When discovery proposes a new one (A is now with
/// C) and A already has a current romantic edge (A with B), the
/// accept flow asks the user whether to flip the old edge to `.past`.
///
/// This is a heuristic, by design: `kind` is a free-text string and
/// the user confirms every demotion, so a false positive only shows
/// a dismissable dialog. Whether two romantic edges can both be
/// current (polyamory) is the user's call, not the system's.
public enum RelationshipConflict {
    /// Lower-cased tokens that mark a `kind` as a romantic-partner
    /// relationship — the class a character usually holds one
    /// current instance of. Matched as substrings so "ex-girlfriend"
    /// and "girlfriend" both hit (status, not kind, decides whether
    /// such an edge is actually live).
    static let exclusiveKindTokens: Set<String> = [
        "girlfriend", "boyfriend", "wife", "husband", "spouse",
        "fiance", "fiancee", "fiancé", "fiancée",
        "lover", "partner", "girl friend", "boy friend",
    ]

    /// True if `kind` reads as a romantic-partner relationship.
    public static func isExclusiveKind(_ kind: String) -> Bool {
        let lc = kind.lowercased()
        return exclusiveKindTokens.contains { lc.contains($0) }
    }

    /// Given a character's existing relationships and the `kind` of a
    /// relationship about to be accepted, return the existing
    /// `.current` relationships in the same exclusive class. A
    /// non-empty result is the cue to prompt the user to demote
    /// them. Empty when the new kind isn't exclusive, or no current
    /// exclusive edge exists.
    public static func conflictingCurrent(
        newKind: String,
        existing: [Relationship]
    ) -> [Relationship] {
        guard isExclusiveKind(newKind) else { return [] }
        return existing.filter {
            $0.status == .current && isExclusiveKind($0.kind)
        }
    }

    /// Merge an accepted relationship into a character's existing
    /// edges. Pure-data; the AppState accept flow calls this after
    /// the user has answered the demote prompt.
    ///
    /// - `demoteConflicting`: when true, every existing current
    ///   romantic edge (other than the one being accepted) flips to
    ///   `.past` — the "A's partner changed" transition. When false,
    ///   prior edges are left untouched (the user declined, or there
    ///   was no conflict).
    /// - The new edge upserts by `(toCharacterId, kind)`: re-accepting
    ///   the same relationship refreshes it rather than duplicating.
    ///   A different `kind` to the same character is a distinct edge.
    public static func applyAccepted(
        to existing: [Relationship],
        newEdge: Relationship,
        demoteConflicting: Bool
    ) -> [Relationship] {
        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .whitespaces)
        }
        let sameSlot: (Relationship) -> Bool = {
            $0.toCharacterId == newEdge.toCharacterId && norm($0.kind) == norm(newEdge.kind)
        }
        var result = existing
        // Demotion only applies when the accepted edge is itself a
        // romantic one — a new friendship never displaces a partner,
        // whatever the flag says.
        if demoteConflicting && isExclusiveKind(newEdge.kind) {
            for i in result.indices {
                guard result[i].status == .current,
                      isExclusiveKind(result[i].kind),
                      !sameSlot(result[i]) else { continue }
                result[i].status = .past
            }
        }
        if let idx = result.firstIndex(where: sameSlot) {
            result[idx] = newEdge
        } else {
            result.append(newEdge)
        }
        return result
    }
}
