import Foundation

/// Streaming-aware companion to `ThinkBlockStripper`. The post-finish
/// stripper still runs as defence-in-depth at generation finish, but
/// with Gemma 4 31B as the writer (which always emits a
/// `<|channel>thought\n...\n<channel|>` wrapper on every generation),
/// the user sees the thinking tags + their content streaming in for
/// the full ~60–120 seconds before they get stripped at the end. This
/// stripper threads the token stream and swallows tokens that fall
/// inside a thinking block, so the editor never inserts them.
///
/// Stateful: each generation gets its own instance, reset on
/// `didStart`. `consume(token)` returns the clean text to insert for
/// that token (may be `""` while inside a thinking block, may be
/// longer than `token` if a previously-buffered partial-tag prefix
/// flushes through). `flush()` at end-of-stream emits any safely-
/// bufferable residue and preserves unclosed thinking blocks (mirrors
/// the post-finish stripper's "don't swallow unclosed" rule).
///
/// Handles two token formats:
/// 1. **Qwen** — `<think>...</think>` (ChatML family).
/// 2. **Gemma 4** — `<|channel>thought\n...\n<channel|>`. Critically
///    Gemma emits the pair even when the thought body is empty, so
///    the stripper handles `<|channel>thought<channel|>` as well as
///    the filled variant.
public struct StreamingThinkBlockStripper {

    /// Which thinking-block format is currently being swallowed, if
    /// any. `.outside` means tokens flush to output (subject to the
    /// partial-tag-suffix hold-back).
    private enum Mode {
        case outside
        case insideQwen
        case insideGemma4
    }

    private var mode: Mode = .outside
    /// Text that has arrived but not yet been classified. While
    /// `.outside`, the trailing suffix is held back if it could be
    /// the start of an opening tag. While `.insideX`, the trailing
    /// suffix is held back if it could be the start of the closing
    /// tag. `consume` and `flush` drain this buffer.
    private var pending: String = ""
    /// Body content swallowed while in an inside state, kept so
    /// `flush` can preserve unclosed leaks verbatim (mirrors the
    /// post-finish stripper's "don't swallow unclosed" rule).
    /// Cleared on every successful close transition.
    private var swallowedBody: String = ""
    /// Set on close-tag transition to swallow whitespace that
    /// arrives in a SUBSEQUENT token (the trailing `\n\n` after
    /// `</think>` often shows up in a token boundary later than the
    /// close itself). Cleared on first non-whitespace character.
    private var swallowLeadingWhitespace: Bool = false

    private static let qwenOpen = "<think>"
    private static let qwenClose = "</think>"
    private static let gemma4Open = "<|channel>thought"
    private static let gemma4Close = "<channel|>"

    public init() {}

    /// Append a streaming token and return the clean text that's
    /// safe to insert into the editor right now. May be empty (we're
    /// holding back) or longer than `token` (a previously-held
    /// prefix is now safe to flush).
    public mutating func consume(_ token: String) -> String {
        pending += token
        return drain()
    }

    /// End-of-stream flush. Releases any pending content that was
    /// being held back as a possible-tag prefix; if we're still
    /// inside an unclosed thinking block at flush time, the partial
    /// leak (opening tag + accumulated body) is preserved verbatim
    /// so the user can see something is wrong (matches the post-
    /// finish stripper's behaviour).
    public mutating func flush() -> String {
        var output = ""
        switch mode {
        case .outside:
            // Anything still pending in the outside state is safe to
            // emit — no more tokens are coming, so a trailing
            // possible-tag prefix is now definitively NOT a tag.
            output = pending
            pending = ""
        case .insideQwen:
            // Unclosed Qwen think block — preserve as-is, including
            // any body content we swallowed while streaming. Matches
            // the post-finish stripper's "don't swallow unclosed"
            // behaviour so the user gets the same final text either
            // way (or worse only by the partial-suffix hold-back).
            output = Self.qwenOpen + swallowedBody + pending
            pending = ""
            swallowedBody = ""
            mode = .outside
        case .insideGemma4:
            output = Self.gemma4Open + swallowedBody + pending
            pending = ""
            swallowedBody = ""
            mode = .outside
        }
        return output
    }

    // MARK: - State machine

    /// Pump the state machine until no more transitions are possible
    /// with the current `pending` buffer. Returns the text to emit.
    private mutating func drain() -> String {
        var output = ""
        var progressed = true
        while progressed {
            progressed = false
            switch mode {
            case .outside:
                progressed = drainOutside(into: &output)
            case .insideQwen:
                progressed = drainInside(close: Self.qwenClose, into: &output)
            case .insideGemma4:
                progressed = drainInside(close: Self.gemma4Close, into: &output)
            }
        }
        return output
    }

    /// In the outside state we look for either opening tag in
    /// `pending`. If found, flush the text before it to output and
    /// transition to the matching inside state with the residue
    /// after the tag. If not found, flush the longest safe prefix
    /// (everything except a trailing suffix that COULD still be a
    /// prefix of either opening tag) and stop.
    private mutating func drainOutside(into output: inout String) -> Bool {
        // Post-close whitespace swallowing: trailing `\n\n` after a
        // `</think>` or `<channel|>` often arrives in a token AFTER
        // the close itself, so the in-place strip during drainInside
        // can't catch it. Eat leading whitespace from `pending`
        // until the first non-whitespace character or the buffer
        // empties, then clear the flag.
        if swallowLeadingWhitespace && !pending.isEmpty {
            while let first = pending.first, first.isNewline || first == " " || first == "\t" {
                pending.removeFirst()
            }
            if !pending.isEmpty {
                swallowLeadingWhitespace = false
            }
        }
        // Earliest opening-tag occurrence wins so we don't miss a
        // Gemma tag that appeared before a later Qwen tag.
        let qwenIdx = pending.range(of: Self.qwenOpen)
        let gemmaIdx = pending.range(of: Self.gemma4Open)
        let target: (Range<String.Index>, Mode)?
        switch (qwenIdx, gemmaIdx) {
        case (.none, .none):
            target = nil
        case (.some(let q), .none):
            target = (q, .insideQwen)
        case (.none, .some(let g)):
            target = (g, .insideGemma4)
        case (.some(let q), .some(let g)):
            if q.lowerBound < g.lowerBound {
                target = (q, .insideQwen)
            } else {
                target = (g, .insideGemma4)
            }
        }
        if let (range, newMode) = target {
            output += pending[..<range.lowerBound]
            pending = String(pending[range.upperBound...])
            mode = newMode
            return true
        }
        // No opening tag in pending. Flush everything except a
        // trailing suffix that could start an opening tag.
        let holdCount = longestSuffixPrefixingAny(of: pending, of: [Self.qwenOpen, Self.gemma4Open])
        let safeEnd = pending.index(pending.endIndex, offsetBy: -holdCount)
        output += pending[..<safeEnd]
        pending = String(pending[safeEnd...])
        return false
    }

    /// In an inside state we look for the closing tag. If found,
    /// drop everything up to and including it (plus trailing
    /// whitespace) and transition back to outside. If not, drop
    /// everything except a trailing suffix that could start the
    /// closing tag (so the next chunk can complete the match).
    private mutating func drainInside(close: String, into output: inout String) -> Bool {
        if let range = pending.range(of: close) {
            // Body up to the close — keep in swallowedBody so a later
            // `flush` on an unclosed run could preserve it. Successful
            // close means we clear it.
            var afterClose = pending[range.upperBound...]
            while let first = afterClose.first, first.isNewline || first == " " || first == "\t" {
                afterClose = afterClose.dropFirst()
            }
            pending = String(afterClose)
            swallowedBody = ""
            mode = .outside
            // Eat whitespace that arrives in a SUBSEQUENT token too.
            swallowLeadingWhitespace = true
            return true
        }
        let holdCount = longestSuffixPrefixingAny(of: pending, of: [close])
        let dropEnd = pending.index(pending.endIndex, offsetBy: -holdCount)
        // Everything before the held suffix is body content — buffer
        // it (not discard) so an unclosed flush can preserve the leak.
        swallowedBody += pending[..<dropEnd]
        pending = String(pending[dropEnd...])
        return false
    }

    /// Returns the length of the longest suffix of `text` that is a
    /// non-empty prefix of any tag in `tags`. Zero if no such
    /// suffix exists. Used to decide how much of `pending` to hold
    /// back across token boundaries: we keep that suffix so the next
    /// chunk might complete a tag match, and flush everything else.
    private func longestSuffixPrefixingAny(of text: String, of tags: [String]) -> Int {
        let textChars = Array(text)
        let maxLen = tags.map(\.count).max() ?? 0
        let upper = min(textChars.count, maxLen)
        for length in stride(from: upper, through: 1, by: -1) {
            let suffix = String(textChars.suffix(length))
            for tag in tags where tag.hasPrefix(suffix) {
                return length
            }
        }
        return 0
    }
}
