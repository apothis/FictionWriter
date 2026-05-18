import Foundation

/// Decides when a character's `intimateAnatomy` may enter the prompt.
///
/// Anatomy detail leaks if it lives in always-on context — the model
/// surfaces it while the character is still clothed, because nothing
/// inside the model gates a detail by narrative state. The fix is
/// structural (research 2026-05-19): don't put it in context until
/// the state warrants it.
///
/// Two conditions, both required:
///   1. The scene is *depicted* — effective explicitness ≥ onScreen.
///   2. *This* character is shown undressed — their name or an alias
///      co-occurs with an undress term in some paragraph of the
///      scene-so-far. Per-character: one character undressing never
///      unlocks another's anatomy. Scanning the whole scene-so-far
///      makes the unlock sticky — once undressed, it stays.
///
/// Limitation: paragraph-scoped name matching can miss a purely
/// pronoun-written undressing. It self-corrects once the character is
/// named near body description; a miss only withholds detail, never
/// leaks it.
public enum AnatomyGate {

    public static let undressTerms: [String] = [
        "naked", "nude", "nudity", "undressed", "undress", "undressing",
        "unclothed", "bare", "exposed", "stripped", "strip", "stripping",
        "topless", "bottomless", "disrobe", "disrobed",
    ]

    /// True when `character`'s intimate anatomy should be injected.
    public static func shouldInject(
        character: Character,
        sceneProseSoFar: String,
        explicitnessLevel: ExplicitnessLevel
    ) -> Bool {
        guard !character.intimateAnatomy
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        switch explicitnessLevel {
        case .onScreen, .graphic, .extreme:
            break
        case .fadeToBlack, .suggestive:
            return false
        }
        return isUndressed(character: character, in: sceneProseSoFar)
    }

    /// Whole-word name/alias co-occurring with an undress term in any
    /// paragraph of the prose.
    public static func isUndressed(character: Character, in prose: String) -> Bool {
        let names = ([character.name] + character.aliases)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !names.isEmpty else { return false }
        for paragraph in prose.components(separatedBy: "\n\n") {
            let lower = paragraph.lowercased()
            if WholeWordMatcher.anyMatch(keys: names, in: lower),
               WholeWordMatcher.anyMatch(keys: undressTerms, in: lower) {
                return true
            }
        }
        return false
    }
}
