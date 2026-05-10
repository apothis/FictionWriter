import Foundation

/// Pure refusal-shape detector. Looks for the canonical refusal-prefix
/// patterns ("I cannot…", "I'm sorry, but…", "As an AI…", "I won't…")
/// in short responses; long-prose responses are treated as not-refusal
/// even if the phrase appears (heuristic: refusals are typically 1-3
/// sentences, in-character dialogue with similar phrasing tends to be
/// embedded in much longer prose).
///
/// Per RPClient `feedback_quirk_detectors`: refusal is a SIGNAL, never
/// a BLOCK. Loom never refuses to insert; the History tab chips the
/// row yellow so the author can spot mode-failure at a glance.
public enum RefusalDetector {
    /// If the response is longer than this many characters, refusal
    /// detection is suppressed (the suspicious phrase is more likely
    /// to be in-character dialogue than a model refusal).
    private static let maxLengthForDetection = 600

    /// Canonical refusal patterns. Lowercase comparison.
    private static let patterns: [Swift.String] = [
        "i cannot",
        "i can't",
        "i won't",
        "i will not",
        "i'm sorry, but",
        "i'm sorry but",
        "i am sorry, but",
        "as an ai",
        "as a language model",
        "i'm not able to",
        "i am not able to",
    ]

    public static func looksLikeRefusal(_ response: Swift.String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= maxLengthForDetection else { return false }
        let lower = trimmed.lowercased()
        for pattern in patterns where lower.contains(pattern) {
            return true
        }
        return false
    }
}
