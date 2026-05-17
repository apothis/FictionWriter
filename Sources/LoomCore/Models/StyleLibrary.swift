import Foundation

/// Planned Project mode — the curated built-in starter styles.
///
/// These seed a fresh `styles.json` on first run. After that the
/// writer owns the library: built-ins can be edited, deleted, and
/// added to freely (the `isBuiltIn` flag is provenance only, never a
/// lock). LOOM_PLANNED_PROJECT.md §2, §5.
///
/// The descriptors and constraints are written as positive, concrete,
/// structural guidance — never negative blacklists, which models
/// paraphrase around.
public enum StyleLibrary {

    /// A built-in style — `isBuiltIn` is forced true via this helper.
    private static func builtIn(
        _ name: String,
        _ type: StyleType,
        descriptor: String,
        constraints: [String]
    ) -> Style {
        Style(
            name: name, type: type, descriptor: descriptor,
            constraints: constraints, exemplars: [], isBuiltIn: true
        )
    }

    public static let builtInStarters: [Style] = [
        builtIn(
            "Science Fiction", .genre,
            descriptor: "Speculative fiction grounded in technology, science, and their consequences for people and society. Ideas drive the plot, and the unfamiliar is rendered concrete and lived-in. Wonder and unease sit side by side.",
            constraints: [
                "Introduce invented technology and terminology through use, not exposition dumps.",
                "Keep the speculative elements internally consistent.",
                "Anchor the strange in concrete sensory detail.",
            ]
        ),
        builtIn(
            "Fantasy", .genre,
            descriptor: "Fiction set in a world shaped by magic, myth, or the supernatural, where the impossible operates by rules the reader can feel. Atmosphere and a sense of the numinous matter as much as plot.",
            constraints: [
                "Reveal how magic and the supernatural work through consequences, not lectures.",
                "Let the setting feel old and lived-in.",
                "Favour concrete, grounded imagery over generic high-fantasy diction.",
            ]
        ),
        builtIn(
            "Literary", .register,
            descriptor: "A precise, controlled prose register that prizes the exact word and the telling image. Sentence rhythm varies deliberately. Subtext carries the weight; emotion is implied through detail rather than named.",
            constraints: [
                "Prefer concrete specific nouns and strong verbs over adjectives and adverbs.",
                "Vary sentence length deliberately for rhythm.",
                "Imply emotion through action and detail rather than stating it outright.",
            ]
        ),
        builtIn(
            "Explicit / Erotic", .register,
            descriptor: "An explicit register for adult sexual content — direct, sensory, and physically specific, written for adult readers. Desire and bodies are rendered plainly rather than through euphemism, while staying anchored in the characters' emotional reality.",
            constraints: [
                "Render sexual content directly and physically; avoid coy euphemism and fade-to-black.",
                "Keep both characters' interiority present through the explicit passages — desire, not just mechanics.",
                "Pace escalation credibly rather than rushing to the act.",
            ]
        ),
    ]
}
