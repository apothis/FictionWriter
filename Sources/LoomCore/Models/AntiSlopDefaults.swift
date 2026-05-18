import Foundation

/// P2c — the curated default anti-slop phrase list.
///
/// "Slop" is the catalogued family of cliché phrasings local models
/// over-produce — "shivers down the spine", "voice barely above a
/// whisper", "a testament to". The phrases below seed a new project's
/// editable `ProjectSettings.antiSlopPhrases`; the author tunes the
/// list per project.
///
/// This is a data resource only. The transport path — feeding the
/// list to KoboldCpp as `banned_strings` (phrase-level backtracking,
/// the architecture the AntiSlop research validates) — is deliberately
/// deferred until that server capability is confirmed.
///
/// Phrases are stored verbatim, lowercase, as substrings; a future
/// matcher decides word-boundary semantics.
public enum AntiSlopDefaults {

    public static let phrases: [String] = [
        // Body-reaction clichés
        "shivers down her spine",
        "shivers down his spine",
        "a shiver down her spine",
        "a shiver down his spine",
        "sent a shiver",
        "her breath hitched",
        "his breath hitched",
        "breath caught in her throat",
        "breath caught in his throat",
        "heart hammered",
        "heart pounded in her chest",
        "heart pounded in his chest",
        "a knot formed in her stomach",
        "a knot formed in his stomach",
        "let out a breath she didn't know she was holding",
        "let out a breath he didn't know he was holding",

        // Voice / expression clichés
        "voice barely above a whisper",
        "barely above a whisper",
        "the corner of her mouth quirked",
        "the corner of his mouth quirked",
        "a ghost of a smile",
        "her eyes sparkled",
        "his eyes sparkled",
        "eyes glinted with mischief",

        // Grand-abstraction clichés
        "a testament to",
        "a symphony of",
        "a kaleidoscope of",
        "a dance as old as time",
        "the air was thick with",
        "a wave of emotion",
        "a mixture of fear and",

        // Explicit-scene euphemism slop
        "her core",
        "his ministrations",
        "ministrations",
        "waves of pleasure",
        "white-hot pleasure",
        "claimed her mouth",
        "claimed his mouth",
        "a low growl",

        // Filler intensifiers
        "couldn't help but",
        "little did she know",
        "little did he know",
        "impossibly",
    ]
}
