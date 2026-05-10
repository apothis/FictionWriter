import Foundation

/// Strips Qwen-style `<think>...</think>` thinking blocks from
/// generated prose. The ChatML prefill `<think>\n\n</think>\n\n`
/// suppresses thinking in most cases, but some prompts still produce
/// a leaked block. This is a post-finish safety net — pure string
/// operation, easy to test.
///
/// Removes the whole block including the tags plus any trailing
/// whitespace (so a block followed by "\n\nReal prose..." cleans up
/// to just "Real prose...").
public enum ThinkBlockStripper {
    public static func strip(_ text: String) -> String {
        let pattern = #"<think>[\s\S]*?</think>\s*"#
        return text.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }
}
