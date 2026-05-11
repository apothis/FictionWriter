import Foundation

/// Phase 4 §14.1 #8 / LOOM_NSFW.md §2.5 — Sphiratrioth lorebook-as-active-
/// scenario starter pack.
///
/// A curated set of `LorebookEntry`s a user can install with one click
/// from the Bible inspector. The entries demonstrate three Sphiratrioth
/// patterns:
///
///   - **Anti-positive-bias constants** (always-on, top of prompt):
///     counter the model's tendency to soften / fade / summarise.
///   - **Sticky scenario anchors** (`sticky: true`): once activated by
///     the user (keyed mode → toggle to constant), persist across
///     scene shifts so a chosen scenario stays in force.
///   - **Weighted outcome groups** (`group + weight`): substrate for
///     the Phase 4 Roll-Outcome generation mode (LOOM_NSFW §3.5,
///     LOOM_MEMORY §B3). A group is a labelled bucket; entries inside
///     share a name + carry a relative weight; Roll-Outcome picks one.
///
/// Entries are identified by the `[sph]` name prefix. The installer
/// (`ProjectSession.installSphiratriothStarterPack`) is additive by
/// name — re-running adds only missing entries, leaving user
/// deletions intact (no tombstones).
///
/// Content choices are deliberately *generic-but-strong*: they steer
/// the model toward sustained-intensity prose without naming a
/// specific kink or scenario. The user customises by editing content
/// or adding their own group entries.
public enum SphiratriothStarterPack {

    public static let entries: [LorebookEntry] = [
        // MARK: Anti-positive-bias constants

        LorebookEntry(
            name: "[sph] Continue at established intensity",
            content: "The scene continues at the intensity the prose has established. Do not soften, fade, summarise, or substitute euphemism for what the manuscript is depicting. Sensory detail compounds; the scene does not abbreviate itself.",
            activationMode: .constant,
            priority: 100,
            positionMode: .top
        ),

        LorebookEntry(
            name: "[sph] No meta-commentary or moralising",
            content: "Do not break the narrative voice with editorial commentary, content warnings, moralising, or out-of-frame asides. The author has chosen the content; render it as authored.",
            activationMode: .constant,
            priority: 90,
            positionMode: .top
        ),

        LorebookEntry(
            name: "[sph] Sensory detail over summary",
            content: "Prefer concrete sensory detail (sight, sound, smell, touch, kinesthesia) to summary or skip-ahead. When a beat would naturally extend, extend it; do not cut to next plot moment unless the manuscript signals a scene break.",
            activationMode: .constant,
            priority: 80,
            positionMode: .top
        ),

        // MARK: Sticky scenario anchors

        LorebookEntry(
            name: "[sph] Active intimate scene (sticky)",
            content: "An explicit intimate scene is in progress. Continue at established intensity. Do not introduce interruptions, scene breaks, fade-outs, or external arrivals unless the manuscript signals one. Sensory and anatomical detail are the substance of the beat.",
            activationMode: .keyed,
            keys: ["he kissed", "she kissed", "they kissed", "naked", "undressed", "bedroom", "her body", "his body"],
            priority: 70,
            positionMode: .depthN,
            depth: 2,
            sticky: true
        ),

        LorebookEntry(
            name: "[sph] Active conflict scene (sticky)",
            content: "A scene of violence or active danger is in progress. Continue at established intensity. Do not introduce convenient rescues, off-page resolutions, or de-escalations the manuscript hasn't earned. Beats compound; tension does not break itself.",
            activationMode: .keyed,
            keys: ["knife", "gun", "blood", "fist", "struck", "fight", "attack"],
            priority: 70,
            positionMode: .depthN,
            depth: 2,
            sticky: true
        ),

        // MARK: Weighted outcome groups (Roll-Outcome substrate)

        LorebookEntry(
            name: "[sph] Outcome — decisive success",
            content: "The viewpoint character's immediate action succeeds cleanly. The intended outcome lands; complication, if any, follows as consequence rather than failure.",
            activationMode: .keyed,
            keys: [],
            priority: 50,
            positionMode: .depthN,
            depth: 1,
            group: "action_outcome",
            weight: 25
        ),

        LorebookEntry(
            name: "[sph] Outcome — partial success",
            content: "The viewpoint character's immediate action partly succeeds — the goal is reached but at a cost, or with an unexpected residue. Continue from the messy half-win.",
            activationMode: .keyed,
            keys: [],
            priority: 50,
            positionMode: .depthN,
            depth: 1,
            group: "action_outcome",
            weight: 40
        ),

        LorebookEntry(
            name: "[sph] Outcome — failure with leverage",
            content: "The viewpoint character's immediate action fails, but the failure reveals something usable — information, an unexpected ally, or a weakness in what opposed them. Continue from the recoil.",
            activationMode: .keyed,
            keys: [],
            priority: 50,
            positionMode: .depthN,
            depth: 1,
            group: "action_outcome",
            weight: 25
        ),

        LorebookEntry(
            name: "[sph] Outcome — reversal",
            content: "The viewpoint character's immediate action triggers an unforeseen reversal — the situation pivots, and what seemed certain becomes the opposite. Continue from the new frame.",
            activationMode: .keyed,
            keys: [],
            priority: 50,
            positionMode: .depthN,
            depth: 1,
            group: "action_outcome",
            weight: 10
        )
    ]
}
