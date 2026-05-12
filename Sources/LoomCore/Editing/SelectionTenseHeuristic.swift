import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Classification of the dominant narrative tense of a prose
/// selection. `.unknown` is a deliberate abstention — return it when
/// the input has too few verbs or the signal is roughly split, so the
/// rewriteTense picker keeps both Past/Present entries enabled and
/// falls back to a tray note on click.
public enum SelectionTense: String, Equatable {
    case past
    case present
    case unknown
}

/// Phase 4 §15.9 — heuristic source-tense detector for the
/// rewriteTense no-op-target guard. Both Qwen and Gemma reliably
/// invent unrelated tense shifts when asked to rewrite to a tense the
/// source is already in (past+past → present; present+present →
/// future). Prompt-side fixes failed twice — the right fix is upstream
/// at the picker. See HANDOFF.md §15.8 "rewriteTense no-op-target
/// failure mode" for the diagnosis.
///
/// Approach: walk the selection with `NLTagger` (lexicalClass +
/// lemma) to identify finite-verb tokens, ignore tokens inside quoted
/// dialogue spans, and classify each verb as past / present /
/// ambiguous via lemma + surface-form morphology. The lemma is the
/// load-bearing signal — surface "read" / "set" / "put" are tense-
/// ambiguous in isolation but the tagger picks them apart most of the
/// time, and when it can't, the heuristic abstains.
public enum SelectionTenseHeuristic {

    /// Verdict thresholds. Picked to be permissive: a single verb or
    /// a tight split returns `.unknown` rather than guess wrong.
    private static let minVerbsForVerdict = 2
    /// Majority ratio: ≥ 0.6 of the classified verbs must agree.
    private static let majorityRatio = 0.6

    public static func classify(_ text: String) -> SelectionTense {
        let narrative = stripQuotedDialogue(text)
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        var pastCount = 0
        var presentCount = 0

        enumerateVerbs(in: narrative) { surface, lemma in
            switch classifyVerb(surface: surface, lemma: lemma) {
            case .past: pastCount += 1
            case .present: presentCount += 1
            case .unknown: break
            }
        }

        let total = pastCount + presentCount
        guard total >= minVerbsForVerdict else { return .unknown }

        let pastShare = Double(pastCount) / Double(total)
        let presentShare = Double(presentCount) / Double(total)
        if pastShare >= majorityRatio { return .past }
        if presentShare >= majorityRatio { return .present }
        return .unknown
    }

    // MARK: - Dialogue exclusion

    /// Remove text inside paired straight or curly double-quote runs.
    /// Single-quote contractions ("don't") are left alone — we only
    /// strip double-quoted dialogue spans so the narrative voice
    /// dominates the verdict.
    private static func stripQuotedDialogue(_ text: String) -> String {
        var out = ""
        var inQuote = false
        for ch in text {
            switch ch {
            case "\"", "\u{201C}", "\u{201D}":
                inQuote.toggle()
            default:
                if !inQuote { out.append(ch) }
            }
        }
        return out
    }

    // MARK: - Verb enumeration

    private static func enumerateVerbs(in text: String, _ body: (_ surface: String, _ lemma: String?) -> Void) {
        guard !text.isEmpty else { return }
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let range = text.startIndex ..< text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            guard tag == .verb else { return true }
            let surface = String(text[tokenRange]).lowercased()
            var lemma: String? = nil
            if let lemmaTag = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0 {
                lemma = lemmaTag.rawValue.lowercased()
            }
            body(surface, lemma)
            return true
        }
        #endif
    }

    // MARK: - Per-verb classification

    private enum VerbTense { case past, present, unknown }

    /// Decide tense for one verb token. The lemma tells us the
    /// dictionary form; the surface form's relationship to the lemma
    /// reveals tense. We handle the common irregulars explicitly
    /// because their surface forms diverge sharply from their lemmas
    /// (was/were ← be, had ← have, took ← take, etc.).
    private static func classifyVerb(surface: String, lemma: String?) -> VerbTense {
        // Explicit irregulars — most-common forms, both auxiliaries
        // and main verbs. Listed by surface form; the lemma is
        // informational, not load-bearing here.
        if pastIrregulars.contains(surface) { return .past }
        if presentIrregulars.contains(surface) { return .present }

        guard let lemma = lemma, !lemma.isEmpty, lemma != surface else {
            // Surface == lemma → bare infinitive / non-3rd-singular
            // present ("walk", "turn"). Treat as present.
            return (lemma != nil && lemma == surface) ? .present : .unknown
        }

        // Surface ≠ lemma → check regular -ed past or -s present.
        if surface.hasSuffix("ed") { return .past }
        if surface.hasSuffix("s") && !surface.hasSuffix("ss") {
            // 3rd-person-singular present ("walks", "turns").
            return .present
        }
        if surface.hasSuffix("ing") {
            // Bare "-ing" is ambiguous (participle, gerund). The
            // auxiliary lookup above handles "is walking" /
            // "was walking" via the auxiliary token itself.
            return .unknown
        }
        return .unknown
    }

    /// Common irregular past-tense forms + past auxiliaries.
    private static let pastIrregulars: Set<String> = [
        // be
        "was", "were",
        // have
        "had",
        // do
        "did",
        // modals + past forms
        "would", "could", "should", "might",
        // common irregular main verbs
        "said", "went", "saw", "took", "came", "got", "made", "knew",
        "found", "thought", "felt", "told", "gave", "kept", "left",
        "held", "stood", "sat", "ran", "began", "broke", "brought",
        "chose", "drew", "drove", "ate", "fell", "flew", "forgot",
        "grew", "heard", "hid", "kept", "laid", "led", "lost", "meant",
        "met", "paid", "put", "read", "rose", "ran", "sang", "sent",
        "shook", "shone", "shot", "showed", "shut", "slept", "spoke",
        "spent", "stood", "struck", "swore", "swung", "threw", "wore",
        "won", "wrote", "lay", "leaned", "turned", "walked",
        // -ed forms that the tagger sometimes returns as lemma-equal
        "leaned", "nodded", "smiled", "frowned", "whispered",
    ]

    /// Common irregular present-tense forms + present auxiliaries.
    private static let presentIrregulars: Set<String> = [
        // be
        "is", "are", "am",
        // have
        "have", "has",
        // do
        "do", "does",
        // modals (present)
        "can", "will", "shall", "may", "must",
    ]
}
