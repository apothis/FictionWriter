import Foundation

/// Planned Project mode — the curated built-in starter styles.
///
/// These seed a fresh `styles.json` on first run. After that the
/// writer owns the library: built-ins can be edited, deleted, and
/// added to freely (the `isBuiltIn` flag is provenance only, never a
/// lock). LOOM_PLANNED_PROJECT.md §2, §5.
///
/// Descriptors are bespoke. The constraint lists were cross-checked
/// against two open sources (LOOM_PLANNED_PROJECT §3.4): the
/// EQ-Bench `creative-writing-bench` quality criteria (MIT) — its
/// failure patterns (tell-don't-show, purple prose, meandering,
/// amateurish, unearned transformations) — and the recurring craft
/// patterns of the SillyTavern community explicit-writing presets
/// (plain direct language over euphemism, show-don't-tell carried
/// into explicit scenes, anti-repetition, dynamic sentence rhythm),
/// paraphrased rather than copied. Constraints are written as
/// positive, concrete, structural guidance — never blacklists.
public enum StyleLibrary {

    /// A built-in style — `isBuiltIn` is forced true via this helper.
    /// The id is derived deterministically from name + type: built-ins
    /// have no `styles.json` to persist an id, so a random `UUID()`
    /// would differ every launch and a project's `assignedStyleIds`
    /// (which reference these built-ins) would stop resolving after a
    /// relaunch — silently dropping the writer's chosen styles.
    private static func builtIn(
        _ name: String,
        _ type: StyleType,
        descriptor: String,
        constraints: [String]
    ) -> Style {
        Style(
            id: stableStyleID(name: name, type: type),
            name: name, type: type, descriptor: descriptor,
            constraints: constraints, exemplars: [], isBuiltIn: true
        )
    }

    /// A stable, process-independent UUID for a built-in starter
    /// style, derived from its name + type via FNV-1a (Foundation's
    /// `Hasher` is per-process randomised and can't be used here).
    /// Pure function — the same inputs yield the same id in every
    /// process and on every machine.
    public static func stableStyleID(name: String, type: StyleType) -> UUID {
        func fnv1a(_ s: String) -> UInt64 {
            var h: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in s.utf8 {
                h ^= UInt64(byte)
                h = h &* 0x0000_0100_0000_01B3
            }
            return h
        }
        func bytes(_ v: UInt64) -> [UInt8] {
            (0..<8).map { UInt8((v >> (8 * (7 - $0))) & 0xFF) }
        }
        let b = bytes(fnv1a("loom.style/\(type.rawValue)/\(name)"))
            + bytes(fnv1a("\(name)/\(type.rawValue)/loom.style"))
        return UUID(uuid: (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        ))
    }

    public static let builtInStarters: [Style] = genres + registers

    /// Resolve a project's `assignedStyleIds` against a style library
    /// — id order is preserved, ids not in the library (a deleted
    /// style) are dropped.
    public static func resolve(_ ids: [UUID], in library: [Style]) -> [Style] {
        let byId = Dictionary(
            library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { byId[$0] }
    }

    /// Insert or replace `style` in `library`, matched by id. A new id
    /// is appended; an existing id is replaced in place (order kept).
    /// The style-library editor's create + edit both route through this.
    public static func upserting(_ style: Style, into library: [Style]) -> [Style] {
        var out = library
        if let idx = out.firstIndex(where: { $0.id == style.id }) {
            out[idx] = style
        } else {
            out.append(style)
        }
        return out
    }

    /// Remove the style with `id` from `library`. A no-op if absent.
    public static func removing(id: UUID, from library: [Style]) -> [Style] {
        library.filter { $0.id != id }
    }

    // MARK: - Genre styles

    private static let genres: [Style] = [
        builtIn(
            "Science Fiction", .genre,
            descriptor: "Speculative fiction grounded in technology, science, and their consequences for people and society. Ideas drive the plot, and the unfamiliar is rendered concrete and lived-in. Wonder and unease sit side by side.",
            constraints: [
                "Introduce invented technology and terminology through use and consequence, never exposition dumps.",
                "Keep the speculative premise internally consistent and follow its implications honestly.",
                "Anchor the unfamiliar in concrete sensory detail; avoid generic sci-fi cliché.",
            ]
        ),
        builtIn(
            "Fantasy", .genre,
            descriptor: "Fiction set in a world shaped by magic, myth, or the supernatural, where the impossible operates by rules the reader can feel. Atmosphere and a sense of the numinous matter as much as plot.",
            constraints: [
                "Reveal how magic and the supernatural work through consequence, not lore lectures.",
                "Let the setting feel old and lived-in through specific, telling detail.",
                "Favour concrete, grounded imagery over generic high-fantasy diction and cliché.",
            ]
        ),
        builtIn(
            "Dark Fantasy / Grimdark", .genre,
            descriptor: "Fantasy stripped of comfort — a world where power corrupts, victory costs, and morality is grey. The supernatural threatens rather than delights. Bleak, but not without flickers of meaning.",
            constraints: [
                "Let consequences land hard and stay landed; reversals and transformations must be earned.",
                "Render violence and hardship with weight, not relish.",
                "Keep characters morally compromised but comprehensible and consistent.",
            ]
        ),
        builtIn(
            "Urban Fantasy", .genre,
            descriptor: "The supernatural hidden inside the modern world — magic in cities, monsters behind ordinary doors. The mundane and the uncanny rub against each other constantly.",
            constraints: [
                "Ground the supernatural in a recognisable contemporary setting.",
                "Treat magic as an open secret with its own rules, costs, and politics.",
                "Keep the city itself a present, specific character in the prose.",
            ]
        ),
        builtIn(
            "Horror", .genre,
            descriptor: "Fiction built to unsettle and frighten. Dread is constructed slowly through atmosphere and implication, and the worst is often what the reader supplies. Fear of the body, the unknown, and the wrong-made-familiar.",
            constraints: [
                "Build dread through pacing and restraint before any reveal.",
                "Make the ordinary turn wrong rather than relying on spectacle or gore alone.",
                "Anchor fear in concrete bodily and sensory detail; show it, do not summarise it.",
            ]
        ),
        builtIn(
            "Thriller", .genre,
            descriptor: "Propulsive, high-stakes fiction driven by tension and momentum. The protagonist is under pressure and time is short. Every scene tightens the screw.",
            constraints: [
                "End scenes on tension or a turn that pulls the reader forward; never let the plot meander.",
                "Keep stakes concrete and personal to the protagonist.",
                "Favour forward momentum over digression.",
            ]
        ),
        builtIn(
            "Mystery / Crime", .genre,
            descriptor: "Fiction organised around a crime and its unravelling. Information is revealed, withheld, and misdirected with care, and the reader is invited to piece things together. Logic and consequence matter.",
            constraints: [
                "Plant clues fairly and track exactly what the reader knows.",
                "Let the investigation drive scene structure.",
                "Make every revelation recontextualise what came before, not merely add to it.",
            ]
        ),
        builtIn(
            "Noir", .genre,
            descriptor: "Crime fiction in a morally shadowed key — compromised protagonists, corruption that reaches everywhere, a fatalistic mood. Cynical, terse, and atmospheric. Nobody comes out clean.",
            constraints: [
                "Keep the prose terse and the mood fatalistic.",
                "Let setting and weather carry the atmosphere; resist purple description.",
                "Give every character an angle and a credible, lived-in voice.",
            ]
        ),
        builtIn(
            "Romance", .genre,
            descriptor: "Fiction centred on the development of a relationship, with the emotional connection as the spine of the plot. Longing, obstacle, and intimacy drive every beat, and the arc bends toward emotional payoff.",
            constraints: [
                "Keep the relationship the engine of the plot, not a subplot.",
                "Build intimacy through specific, earned moments; show attraction rather than declaring it.",
                "Let obstacles genuinely test the connection rather than merely delay it.",
            ]
        ),
        builtIn(
            "Erotica", .genre,
            descriptor: "Fiction in which sexual desire and relationships are the central subject and engine of the story, written for adult readers. The erotic content is the plot, not an ornament to it.",
            constraints: [
                "Make sexual desire the story's central engine, not a digression.",
                "Give the characters specific wants, histories, and stakes so the eroticism carries weight.",
                "Let tension build and release across the whole arc, not only within scenes.",
            ]
        ),
        builtIn(
            "Historical Fiction", .genre,
            descriptor: "Fiction set in a realised past, where period detail, social texture, and the constraints of the era shape character and plot. The world feels researched and lived-in without lecturing.",
            constraints: [
                "Render period detail through daily life, objects, and speech, not exposition.",
                "Let the era's social constraints bear on the characters' choices.",
                "Keep diction evocative of the period without tipping into archaic pastiche.",
            ]
        ),
        builtIn(
            "Adventure", .genre,
            descriptor: "Fiction of movement, danger, and discovery — journeys, escapes, and physical stakes. The protagonist is tested against the world, and pace and place carry the reader forward.",
            constraints: [
                "Keep the plot in motion through physical stakes and changing locations.",
                "Render action clearly and concretely, beat by beat.",
                "Make the landscape itself an obstacle and a presence.",
            ]
        ),
        // LitRPG family — fiction built on explicit game systems.
        // "All LitRPG is GameLit; not all GameLit is LitRPG": LitRPG
        // makes visible RPG stats load-bearing, GameLit keeps game
        // elements as lighter texture. The variety styles below cover
        // the established subgenres.
        builtIn(
            "LitRPG", .genre,
            descriptor: "Fiction in which explicit role-playing-game mechanics — levels, stats, skills, classes, quests, and system messages — are a visible, load-bearing part of the story. The reader follows the numbers as the character grows, and the mechanics are fused to plot and character rather than decorative.",
            constraints: [
                "Surface game mechanics explicitly — levels, stats, skills, quests, system notifications — and let the reader watch progression happen.",
                "Keep the underlying system internally consistent: track numbers, costs, and rules, and honour them.",
                "Tie every mechanical gain to a choice or consequence in the story — never numbers for their own sake.",
                "Keep the prose clear, modern, and accessible; favour momentum over ornament.",
            ]
        ),
        builtIn(
            "GameLit", .genre,
            descriptor: "Fiction set in or shaped by a world that runs on game-like systems, where those elements colour the story without dominating it. Skill trees, classes, and game logic are present as texture and backdrop while the characters and plot stay in the foreground.",
            constraints: [
                "Let game-like systems flavour the world without making stat-tracking the point of every scene.",
                "Keep characters and plot in the foreground; mechanics serve the story, not the reverse.",
                "Introduce game elements naturally, as part of how the world simply works.",
            ]
        ),
        builtIn(
            "Dungeon Core", .genre,
            descriptor: "LitRPG told from the dungeon's side — the protagonist is the dungeon core itself, growing, designing rooms, breeding monsters, and defending against the adventurers who come to plunder it. Strategy, management, and creative building drive the story.",
            constraints: [
                "Keep the dungeon's growth, design choices, and resource management central to the plot.",
                "Render the protagonist's non-human perspective consistently — it perceives and reasons as a dungeon, not a person.",
                "Make each expansion and defence a deliberate, consequential choice the reader can follow.",
            ]
        ),
        builtIn(
            "System Apocalypse", .genre,
            descriptor: "A LitRPG of catastrophe: a 'System' descends on the ordinary world, most people die, and the survivors are thrust into a reality of levels, skills, and monsters. Survival, scarcity, and adaptation under sudden brutal rules drive the story.",
            constraints: [
                "Open the world's transformation as a hard rupture and keep its stakes lethal and immediate.",
                "Ground the System's arrival in a recognisable real world turned deadly.",
                "Make survival, scarcity, and adaptation — not just leveling — the engine of tension.",
            ]
        ),
        builtIn(
            "VRMMO LitRPG", .genre,
            descriptor: "LitRPG set inside a literal virtual-reality game world that characters log into and out of. The game's rules are explicit and absolute, but the story plays the boundary between the virtual and the real — what is at stake when the game is only a game, and when it stops being one.",
            constraints: [
                "Treat the game world's rules as explicit, absolute, and consistent.",
                "Keep the line between the virtual and the real present and meaningful to the stakes.",
                "Render the game as a place with its own society, economy, and texture — not just a mechanics layer.",
            ]
        ),
        builtIn(
            "Cultivation LitRPG", .genre,
            descriptor: "LitRPG fused with the cultivation tradition of xianxia and wuxia — characters ascend through ranked realms of power by cultivating qi, body, and spirit, the climb rendered through explicit game-like levels and systems. Martial progression, breakthroughs, and the long road toward transcendence drive the story.",
            constraints: [
                "Structure progression as ranked realms or stages with clear thresholds and breakthroughs.",
                "Render cultivation as disciplined effort — training, insight, and setback — never free power.",
                "Let the world's hierarchy of strength shape its society, its conflicts, and the protagonist's choices.",
            ]
        ),
        builtIn(
            "Cozy LitRPG", .genre,
            descriptor: "Low-stakes, slice-of-life LitRPG — crafting, cooking, farming, shopkeeping, and town-building inside a game-like world. The pleasure is competence, small steady progress, and community rather than danger. Calm and meditative in mood.",
            constraints: [
                "Keep stakes low and human-scaled — a livelihood, a friendship, a small place that thrives.",
                "Let progression come through crafting, building, and everyday competence rather than combat.",
                "Hold a calm, warm, unhurried mood; resolve conflict gently.",
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
                "Vary sentence length and rhythm deliberately so the prose flows naturally.",
                "Imply emotion through action and telling detail rather than naming it — show, don't tell.",
                "Avoid purple prose, show-off vocabulary, and gratuitous metaphor.",
            ]
        ),
        builtIn(
            "Minimalist", .register,
            descriptor: "A sparse, pared-back prose register. Short sentences, plain words, white space. Meaning sits in what is left unsaid, and the reader does the emotional work.",
            constraints: [
                "Cut every word that does not earn its place.",
                "Favour short, declarative sentences and plain words.",
                "State events plainly and let subtext carry the feeling.",
            ]
        ),
        builtIn(
            "Lush / Ornate", .register,
            descriptor: "A rich, dense prose register — long sentences, layered imagery, a sensuous attention to texture and light. The prose itself is part of the pleasure. Maximalist but controlled.",
            constraints: [
                "Build long sentences with deliberate rhythm and clear architecture.",
                "Layer concrete sensory imagery — light, texture, sound — that does real work.",
                "Stay rich without tipping into purple prose or overwrought phrasing.",
            ]
        ),
        builtIn(
            "Pulp", .register,
            descriptor: "Fast, punchy, propulsive prose. Vivid verbs, hard cuts, no fat. Built to be devoured — energy over polish.",
            constraints: [
                "Keep sentences quick and verbs vivid.",
                "Cut hard between beats and trust the reader to keep up.",
                "Favour momentum over decoration; never meander.",
            ]
        ),
        builtIn(
            "Wry / Comic", .register,
            descriptor: "A light, ironic narrative register. Humour comes from observation, timing, and understatement rather than jokes. The narration has a knowing, amused intelligence.",
            constraints: [
                "Land humour through timing and understatement, not signposted punchlines.",
                "Keep the comic voice consistent even in serious moments.",
                "Let irony reveal character rather than merely decorate the prose.",
            ]
        ),
        builtIn(
            "Visceral / Gritty", .register,
            descriptor: "A raw, unflinching prose register. The body, dirt, sweat, and pain are on the page. Sensation is immediate and unsoftened — honest about the physical.",
            constraints: [
                "Render physical sensation directly and immediately.",
                "Do not soften discomfort, violence, or bodily detail.",
                "Keep the prose grounded in the senses; show the body, do not summarise it.",
            ]
        ),
        builtIn(
            "Sensual / Suggestive", .register,
            descriptor: "An eroticism of implication and anticipation. Desire saturates the prose, but the explicit act stays mostly off the page — built through tension, touch, and the charged moment. Heat without the camera following all the way.",
            constraints: [
                "Build erotic tension through anticipation, touch, and charged restraint.",
                "Let scenes crest and then cut or soften rather than depicting the act in full.",
                "Keep desire vivid in subtext, sensation, and what is left unsaid.",
                "Use plain, precise language; avoid euphemism that turns coy or purple.",
            ]
        ),
        builtIn(
            "Explicit / Erotic", .register,
            descriptor: "An explicit register for adult sexual content — direct, sensory, and physically specific, written for adult readers. Desire and bodies are rendered plainly rather than through euphemism, while staying anchored in the characters' emotional reality.",
            constraints: [
                "Render sexual content directly and physically — plain, specific language, not coy euphemism or fade-to-black.",
                "Keep both characters' interiority and voice present throughout: show what they feel and do, not just the mechanics.",
                "Pace escalation credibly, varying paragraph and sentence length to the rhythm of the scene.",
                "Vary sensory detail and phrasing — do not repeat the same words, descriptors, or cadences.",
                "Avoid purple prose and negation-padding; describe plainly what is happening.",
            ]
        ),
        builtIn(
            "Hardcore", .register,
            descriptor: "An intense, fully explicit register for adult sexual content — graphic, unrestrained, and physically detailed, written for adult readers. Nothing fades to black; the prose stays with the act in full sensory detail.",
            constraints: [
                "Depict sexual content fully and graphically, in direct physical detail; nothing fades to black.",
                "Stay in the scene through escalation and climax — no cutaways or summary.",
                "Keep sensory specificity high and concrete throughout.",
                "Vary vocabulary, sensory beats, and sentence structure so intensity never becomes repetitive.",
                "Keep the characters' wants and reactions present even at peak intensity — show, don't tell.",
            ]
        ),
        builtIn(
            "Clean / Non-explicit", .register,
            descriptor: "A register that keeps sexual content off the page entirely. Attraction and romance can be present, but intimacy is implied or closes the door.",
            constraints: [
                "Keep sexual content off the page; imply rather than depict.",
                "Close the scene before explicit intimacy begins.",
                "Convey attraction through emotion, gesture, and subtext.",
            ]
        ),
        // LitRPG-specific registers — the prose-craft side of the
        // genre: how game-system text sits on the page, and the
        // mechanics-forward narrative voice.
        builtIn(
            "LitRPG System Interface", .register,
            descriptor: "A prose register for handling game-system text — level-ups, stat blocks, quest logs, skill tooltips, and notifications. The System's voice is set clearly apart from the narrative prose: terse, neutral, structured, and formatted the same way every time it appears.",
            constraints: [
                "Set system text visibly apart from the narrative prose — as discrete notifications or blocks, not blended into a sentence.",
                "Keep the System's voice terse, neutral, and impersonal — labels, numbers, and short declaratives.",
                "Format every system element consistently — the same structure for stats, quests, and notifications throughout.",
                "Place system blocks so they punctuate the prose rather than interrupt its flow.",
            ]
        ),
        builtIn(
            "Crunchy / Optimizer", .register,
            descriptor: "A narrative register that foregrounds the mechanics — the narration thinks in numbers, builds, and trade-offs, and treats optimisation as a genuine pleasure. The prose stays clear, brisk, and modern, inviting the reader to follow the maths and the decision-making.",
            constraints: [
                "Let the narration reason explicitly in mechanics — costs, ratios, build choices, trade-offs.",
                "Keep the prose clear, modern, and brisk; too much ornament reads as drag.",
                "Make optimisation decisions legible — show the reasoning so the reader can follow it and second-guess it.",
            ]
        ),
    ]
}
