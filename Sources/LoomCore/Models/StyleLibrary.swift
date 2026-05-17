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

    public static let builtInStarters: [Style] = genres + registers

    // MARK: - Genre styles

    private static let genres: [Style] = [
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
            "Dark Fantasy / Grimdark", .genre,
            descriptor: "Fantasy stripped of comfort — a world where power corrupts, victory costs, and morality is grey. The supernatural threatens rather than delights. Bleak, but not without flickers of meaning.",
            constraints: [
                "Let consequences land hard and stay landed.",
                "Render violence and hardship with weight, not relish.",
                "Keep characters morally compromised but comprehensible.",
            ]
        ),
        builtIn(
            "Urban Fantasy", .genre,
            descriptor: "The supernatural hidden inside the modern world — magic in cities, monsters behind ordinary doors. The mundane and the uncanny rub against each other constantly.",
            constraints: [
                "Ground the supernatural in a recognisable contemporary setting.",
                "Treat magic as an open secret with its own rules and politics.",
                "Keep the city itself a presence in the prose.",
            ]
        ),
        builtIn(
            "Horror", .genre,
            descriptor: "Fiction built to unsettle and frighten. Dread is constructed slowly through atmosphere and implication, and the worst is often what the reader supplies. Fear of the body, the unknown, and the wrong-made-familiar.",
            constraints: [
                "Build dread through pacing and restraint before any reveal.",
                "Make the ordinary turn wrong rather than relying on spectacle.",
                "Anchor fear in concrete bodily and sensory detail.",
            ]
        ),
        builtIn(
            "Thriller", .genre,
            descriptor: "Propulsive, high-stakes fiction driven by tension and momentum. The protagonist is under pressure and time is short. Every scene tightens the screw.",
            constraints: [
                "End scenes on tension or a turn that pulls the reader forward.",
                "Keep stakes concrete and personal to the protagonist.",
                "Favour forward momentum over digression.",
            ]
        ),
        builtIn(
            "Mystery / Crime", .genre,
            descriptor: "Fiction organised around a crime and its unravelling. Information is revealed, withheld, and misdirected with care, and the reader is invited to piece things together. Logic and consequence matter.",
            constraints: [
                "Plant clues fairly and track what the reader knows.",
                "Let the investigation drive scene structure.",
                "Make every revelation recontextualise what came before.",
            ]
        ),
        builtIn(
            "Noir", .genre,
            descriptor: "Crime fiction in a morally shadowed key — compromised protagonists, corruption that reaches everywhere, a fatalistic mood. Cynical, terse, and atmospheric. Nobody comes out clean.",
            constraints: [
                "Keep the prose terse and the mood fatalistic.",
                "Let setting and weather carry the atmosphere.",
                "Give every character an angle.",
            ]
        ),
        builtIn(
            "Romance", .genre,
            descriptor: "Fiction centred on the development of a relationship, with the emotional connection as the spine of the plot. Longing, obstacle, and intimacy drive every beat, and the arc bends toward emotional payoff.",
            constraints: [
                "Keep the relationship the engine of the plot, not a subplot.",
                "Build intimacy through specific, earned moments.",
                "Let obstacles test the connection rather than merely delay it.",
            ]
        ),
        builtIn(
            "Erotica", .genre,
            descriptor: "Fiction in which sexual desire and relationships are the central subject and engine of the story, written for adult readers. The erotic content is the plot, not an ornament to it.",
            constraints: [
                "Make sexual desire the story's central engine, not a digression.",
                "Give the characters specific wants, histories, and stakes.",
                "Let tension build and release across the arc, not only within scenes.",
            ]
        ),
        builtIn(
            "Historical Fiction", .genre,
            descriptor: "Fiction set in a realised past, where period detail, social texture, and the constraints of the era shape character and plot. The world feels researched and lived-in without lecturing.",
            constraints: [
                "Render period detail through daily life and objects, not exposition.",
                "Let the era's social constraints bear on the characters' choices.",
                "Keep diction evocative of the period without becoming archaic.",
            ]
        ),
        builtIn(
            "Adventure", .genre,
            descriptor: "Fiction of movement, danger, and discovery — journeys, escapes, and physical stakes. The protagonist is tested against the world, and pace and place carry the reader forward.",
            constraints: [
                "Keep the plot in motion through physical stakes and changing locations.",
                "Render action clearly and concretely.",
                "Make the landscape itself an obstacle and a character.",
            ]
        ),
    ]

    // MARK: - Register styles

    private static let registers: [Style] = [
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
            "Minimalist", .register,
            descriptor: "A sparse, pared-back prose register. Short sentences, plain words, white space. Meaning sits in what is left unsaid, and the reader does the emotional work.",
            constraints: [
                "Cut every word that does not earn its place.",
                "Favour short, declarative sentences.",
                "State events plainly and let subtext carry feeling.",
            ]
        ),
        builtIn(
            "Lush / Ornate", .register,
            descriptor: "A rich, dense prose register — long sentences, layered imagery, a sensuous attention to texture and light. The prose itself is part of the pleasure. Maximalist but controlled.",
            constraints: [
                "Build long sentences with deliberate rhythm and clear architecture.",
                "Layer concrete sensory imagery — light, texture, sound.",
                "Let the prose linger without losing forward motion.",
            ]
        ),
        builtIn(
            "Pulp", .register,
            descriptor: "Fast, punchy, propulsive prose. Vivid verbs, hard cuts, no fat. Built to be devoured — energy over polish.",
            constraints: [
                "Keep sentences quick and verbs vivid.",
                "Cut hard between beats and trust the reader to keep up.",
                "Favour momentum over decoration.",
            ]
        ),
        builtIn(
            "Wry / Comic", .register,
            descriptor: "A light, ironic narrative register. Humour comes from observation, timing, and understatement rather than jokes. The narration has a knowing, amused intelligence.",
            constraints: [
                "Land humour through timing and understatement, not punchlines.",
                "Keep the comic voice consistent even in serious moments.",
                "Let irony reveal character, not just decorate.",
            ]
        ),
        builtIn(
            "Visceral / Gritty", .register,
            descriptor: "A raw, unflinching prose register. The body, dirt, sweat, and pain are on the page. Sensation is immediate and unsoftened — honest about the physical.",
            constraints: [
                "Render physical sensation directly and immediately.",
                "Do not soften discomfort, violence, or bodily detail.",
                "Keep the prose grounded in the senses.",
            ]
        ),
        builtIn(
            "Sensual / Suggestive", .register,
            descriptor: "An eroticism of implication and anticipation. Desire saturates the prose, but the explicit act stays mostly off the page — built through tension, touch, and the charged moment. Heat without the camera following all the way.",
            constraints: [
                "Build erotic tension through anticipation, touch, and charged restraint.",
                "Let scenes crest and then cut or soften rather than depicting the act in full.",
                "Keep desire vivid in subtext and sensation.",
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
        builtIn(
            "Hardcore", .register,
            descriptor: "An intense, fully explicit register for adult sexual content — graphic, unrestrained, and physically detailed, written for adult readers. Nothing fades to black; the prose stays with the act in full sensory detail.",
            constraints: [
                "Depict sexual content fully and graphically, in direct physical detail.",
                "Stay in the scene through escalation and climax — no cutaways.",
                "Keep sensory specificity high throughout.",
            ]
        ),
        builtIn(
            "Clean / Non-explicit", .register,
            descriptor: "A register that keeps sexual content off the page entirely. Attraction and romance can be present, but intimacy is implied or closes the door.",
            constraints: [
                "Keep sexual content off the page; imply rather than depict.",
                "Close the scene before explicit intimacy begins.",
                "Convey attraction through emotion and gesture.",
            ]
        ),
    ]
}
