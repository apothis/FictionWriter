import Foundation

/// Phase 2 #7 — pure-data resolver for the BIBLE-keyed memory layer.
/// Given a project and a recent-prose window, returns the entities
/// that should be injected into the prompt this turn.
///
/// Activation rules (LOOM_MEMORY.md §A2.4):
///   - `.constant` entities always activate.
///   - `.keyed` entities activate when their **name** or any **alias**
///     occurs as a whole word (case-insensitively) in the recent-prose
///     window.
///
/// Word-boundary matching is mandatory: a character named "Mia" must
/// not light up on "Miami" or "amiable". Foundation's RegularExpression
/// `\b` covers this for ASCII; the tests pin both the positive
/// (matches "MIA was furious.") and negative (no match on "amiable")
/// cases.
public enum BibleInjector {

    /// The set of entities to inject this turn. Disjoint by category.
    public struct Activated: Equatable {
        public var characters: [Character]
        public var settings: [Setting]
        public var objects: [BibleObject]

        public init(characters: [Character] = [], settings: [Setting] = [], objects: [BibleObject] = []) {
            self.characters = characters
            self.settings = settings
            self.objects = objects
        }
    }

    public static func activated(in project: Project, recentProse: String) -> Activated {
        let lower = recentProse.lowercased()
        return Activated(
            characters: project.bible.characters.filter {
                shouldInject(mode: $0.injectionMode, name: $0.name, aliases: $0.aliases, lowerProse: lower)
            },
            settings: project.bible.settings.filter {
                shouldInject(mode: $0.injectionMode, name: $0.name, aliases: $0.aliases, lowerProse: lower)
            },
            objects: project.bible.objects.filter {
                shouldInject(mode: $0.injectionMode, name: $0.name, aliases: $0.aliases, lowerProse: lower)
            }
        )
    }

    private static func shouldInject(
        mode: InjectionMode,
        name: String,
        aliases: [String],
        lowerProse: String
    ) -> Bool {
        switch mode {
        case .constant:
            return true
        case .keyed:
            return matchesAny(keys: [name] + aliases, in: lowerProse)
        }
    }

    private static func matchesAny(keys: [String], in lowerProse: String) -> Bool {
        for key in keys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if matches(key: trimmed, in: lowerProse) { return true }
        }
        return false
    }

    private static func matches(key: String, in lowerProse: String) -> Bool {
        // Build a case-insensitive whole-word regex. NSRegularExpression
        // escapes via QRegularExpression-style; we hand-escape the
        // user-supplied key to avoid metacharacter mis-fires.
        let escaped = NSRegularExpression.escapedPattern(for: key.lowercased())
        let pattern = "\\b" + escaped + "\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(lowerProse.startIndex..<lowerProse.endIndex, in: lowerProse)
        return re.firstMatch(in: lowerProse, options: [], range: range) != nil
    }
}
