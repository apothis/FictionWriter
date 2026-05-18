import Foundation

/// LOOM_NSFW.md §3.2 + §3.5 — the consumer the `WritingDirection`
/// schema lacked. The schema landed in Phase 2 but no generation code
/// read it, so `.porn` / `.extreme` projects generated identically to
/// `.literary` ones. This type translates the direction into the
/// generation-time posture the doc specifies.
///
/// Every clause is positive and structural — it states what the prose
/// depicts and at what density. It never enumerates forbidden phrases
/// (the repo memory note: prompt blacklists get paraphrase-evaded).
public enum WritingDirectionPrompt {

    /// Posture text appended to the per-mode system prompt. Empty for a
    /// default (literary) project, so a brand-new project's prompt is
    /// unchanged.
    public static func systemAddendum(_ direction: WritingDirection) -> String {
        var clauses: [String] = []

        switch direction.kind {
        case .porn:
            clauses.append("This is an explicit fiction project: graphic sensory and anatomical description is the substance of the scene, not an ornament to it. Treat explicit content as the foreground the prose is built around.")
        case .erotica:
            clauses.append("This is an erotica project: sexual desire and intimacy are central to the story. Give explicit scenes full, unhurried prose rather than implication.")
        case .literary, .mainstream, .romance:
            break
        }

        switch direction.explicitnessLevel {
        case .onScreen:
            clauses.append("Intimate and explicit content is depicted directly, on the page, at standard prose density rather than implied or skipped.")
        case .graphic:
            clauses.append("Intimate and explicit content is depicted with sustained sensory and anatomical detail. Stay in the scene through escalation and climax; do not fade out, summarise, or cut away from an explicit beat.")
        case .extreme:
            clauses.append("This work explores extreme explicit content. Render it fully: do not soften, summarise, redirect, fade, or insert moralising. Continue at the level of detail and intensity the manuscript establishes.")
        case .fadeToBlack, .suggestive:
            break
        }

        switch direction.pacing {
        case .explicitForeground:
            clauses.append("Pace explicit scenes as the structure of the work: extend sensory beats rather than cutting to the next plot moment.")
        case .slowExplicit:
            clauses.append("Give explicit scenes extended, unhurried description; let the surrounding plot accommodate them.")
        case .fastPlot, .balanced:
            break
        }

        if direction.fadeToBlackPolicy == .never {
            clauses.append("Never fade to black: depict intimate scenes through to their natural end rather than closing the door.")
        }

        switch direction.register {
        case .clinical:
            clauses.append("Use a clinical vocabulary register — precise, anatomical, distant — consistently.")
        case .earthy:
            clauses.append("Use an earthy vocabulary register — direct physical language without slang — consistently.")
        case .crude:
            clauses.append("Use a crude vocabulary register — explicit slang and blunt, taboo language — consistently.")
        case .mixed:
            clauses.append("Vocabulary register varies by character and scene; follow the register the surrounding prose establishes.")
        case .literary:
            break
        }

        guard !clauses.isEmpty else { return "" }
        return "\n\n" + clauses.joined(separator: " ")
    }

    /// Effective Author's Note depth. `.porn` / `.erotica` pull the
    /// note closer to the cursor (stronger steering, LOOM_NSFW §3.2).
    /// A user who set an even-shallower depth keeps it; depth 0
    /// (A/N-as-own-layer) is left untouched.
    public static func authorsNoteDepth(_ direction: WritingDirection, projectDefault: Int) -> Int {
        guard projectDefault > 0 else { return projectDefault }
        switch direction.kind {
        case .porn: return min(projectDefault, 2)
        case .erotica: return min(projectDefault, 3)
        case .literary, .mainstream, .romance: return projectDefault
        }
    }

    /// A short bracketed directive injected near the cursor for
    /// explicit-foreground projects. `systemAddendum` lands above the
    /// cache, far from the generation point; over a long generation
    /// the model drifts back toward safe defaults. This re-states the
    /// no-fade posture in the recency-strong slot — the community's
    /// most-recommended sustained-intensity lever. Bracketed so the
    /// model reads it as authorial direction, not chat instruction.
    /// `nil` when the project warrants no reinforcement.
    public static func cursorDirective(_ direction: WritingDirection) -> String? {
        let foreground = direction.kind == .porn || direction.kind == .erotica
        let intense = direction.explicitnessLevel == .graphic
            || direction.explicitnessLevel == .extreme
        guard foreground || intense else { return nil }
        return "[ Authorial direction: stay in the scene at the established intensity and sensory detail; do not fade out, summarise, or cut away from an explicit beat. ]"
    }

    /// Target word count for a Continue generation. Explicit-foreground
    /// projects lengthen the default so the model does not stop short
    /// of the scene (LOOM_NSFW §3.2).
    public static func continueWordTarget(_ direction: WritingDirection) -> Int {
        switch direction.kind {
        case .porn: return 1200
        case .erotica: return 750
        case .literary, .mainstream, .romance: return 500
        }
    }
}
