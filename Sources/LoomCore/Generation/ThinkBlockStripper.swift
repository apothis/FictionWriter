import Foundation

/// Strips reasoning-mode "thought" wrappers from generated prose.
/// Post-finish safety net — pure string operation, easy to test.
///
/// Handles two distinct token formats observed in production:
///
/// 1. **Qwen-style `<think>...</think>`** (ChatML family). The
///    `<think>\n\n</think>\n\n` prefill in `PromptBuilder` usually
///    suppresses these, but some prompts still produce a leaked
///    block.
///
/// 2. **Gemma 4 reasoning format `<|channel>thought\n
///    [reasoning]<channel|>`** (per [ai.google.dev/gemma/docs/
///    capabilities/thinking][1]). Critically, Gemma 4 emits the
///    tag pair EVEN WHEN THINKING IS DISABLED — with an empty
///    thought block — so this stripper has to handle both the
///    filled and empty variants. Observed live 2026-05-13 against
///    a `gemma-4-31B-it-…-Thinking` GGUF.
///
/// Both formats: removes the whole block including its tags plus
/// any trailing whitespace, so a block followed by "\n\nReal
/// prose..." cleans up to just "Real prose...".
///
/// Defensive: an UNCLOSED opening tag (model truncated mid-think)
/// is left intact rather than swallowing the rest of the prose —
/// preserves the partial-leak as a visible signal to the user.
///
/// [1]: https://ai.google.dev/gemma/docs/capabilities/thinking
public enum ThinkBlockStripper {
    public static func strip(_ text: String) -> String {
        // Order matters only as a tidiness preference — the two
        // patterns don't overlap so the result is the same either
        // way. Both are non-greedy across whitespace + non-WS
        // (`[\s\S]*?`) so multi-line bodies match correctly.
        var out = text
        let qwenPattern = #"<think>[\s\S]*?</think>\s*"#
        out = out.replacingOccurrences(of: qwenPattern, with: "", options: .regularExpression)
        let gemma4Pattern = #"<\|channel>thought[\s\S]*?<channel\|>\s*"#
        out = out.replacingOccurrences(of: gemma4Pattern, with: "", options: .regularExpression)
        return out
    }
}
