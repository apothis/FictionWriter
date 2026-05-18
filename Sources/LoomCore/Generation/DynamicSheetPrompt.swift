import Foundation

/// P2b — activation + prompt rendering for `DynamicSheet`.
///
/// Activation mirrors the lorebook: `alwaysOn` sheets inject on every
/// generation; the rest inject only when a participant character (or
/// the sheet's own name) appears as a whole word in the recent prose.
public enum DynamicSheetInjector {

    public static func activated(
        dynamics: [DynamicSheet],
        characters: [Character],
        recentProse: String
    ) -> [DynamicSheet] {
        let lowerProse = recentProse.lowercased()
        let charById = Dictionary(
            characters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return dynamics.filter { sheet in
            guard sheet.enabled else { return false }
            if sheet.alwaysOn { return true }
            var keys = [sheet.name]
            for pid in sheet.participantIds {
                if let name = charById[pid]?.name { keys.append(name) }
            }
            return WholeWordMatcher.anyMatch(keys: keys, in: lowerProse)
        }
    }
}

/// Renders activated `DynamicSheet`s into a prompt block. Each sheet
/// becomes a labelled spec; empty fields are omitted so the model sees
/// only what the author defined.
public enum DynamicSheetPrompt {

    public static func render(_ dynamics: [DynamicSheet]) -> String {
        let blocks = dynamics.compactMap { block($0) }
        return blocks.joined(separator: "\n\n")
    }

    private static func block(_ d: DynamicSheet) -> String? {
        var lines: [String] = []
        func add(_ label: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { lines.append("  \(label): \(v)") }
        }
        add("Roles", d.roles)
        add("Wants", d.wants)
        add("Soft limits", d.softLimits)
        add("Hard limits", d.hardLimits)
        add("Safeword", d.safeword)
        add("Arc", d.arc)
        guard !lines.isEmpty else { return nil }
        let header = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = header.isEmpty ? "Relationship dynamic" : "Relationship dynamic — \(header)"
        return "[ \(title):\n" + lines.joined(separator: "\n") + " ]"
    }
}
