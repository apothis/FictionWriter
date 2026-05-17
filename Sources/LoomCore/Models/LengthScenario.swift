import Foundation

/// Planned Project mode — the manuscript-length presets the writer
/// picks during guided setup. Each preset carries a representative
/// `targetWordCount`, which `OutlineSizing` turns into deterministic
/// scene/chapter counts (LOOM_PLANNED_PROJECT.md §3.3, §4).
///
/// Word-count bands are industry-standard and stable. A free-form
/// custom target is deliberately not modelled here — `Project`
/// already carries `targetWordCount`, and a custom case would only
/// be added if a writer actually asks for it.
public enum LengthScenario: String, Codable, Equatable, CaseIterable {
    case flashFiction
    case shortStory
    case novelette
    case novella
    case novel

    /// Representative target word count — the basis `OutlineSizing`
    /// uses to derive scene and chapter counts.
    public var targetWordCount: Int {
        switch self {
        case .flashFiction: return 750
        case .shortStory: return 4_000
        case .novelette: return 12_000
        case .novella: return 28_000
        case .novel: return 80_000
        }
    }

    /// The industry-standard word-count band for this format —
    /// display only (the length picker shows it).
    public var wordRange: ClosedRange<Int> {
        switch self {
        case .flashFiction: return 100...1_000
        case .shortStory: return 1_000...7_500
        case .novelette: return 7_500...17_500
        case .novella: return 17_500...40_000
        case .novel: return 40_000...120_000
        }
    }

    /// Human-readable label for the length picker.
    public var displayName: String {
        switch self {
        case .flashFiction: return "Flash fiction"
        case .shortStory: return "Short story"
        case .novelette: return "Novelette"
        case .novella: return "Novella"
        case .novel: return "Novel"
        }
    }
}
