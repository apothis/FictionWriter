import Foundation

/// GLiNER native entity detector — phase 4a: input construction.
///
/// Pure-data helpers that turn a scene of prose into the structures
/// GLiNER's ONNX graph needs. The stateful pieces — tokenisation,
/// the ONNX session, decode — compose these in later phases.
public enum GLiNERInputs {
    /// GLiNER's max span width: each start word enumerates spans of
    /// width 0…11 (12 offsets). From `gliner_config.json`.
    public static let maxSpanWidth = 12

    /// A whitespace-split word with its character span in the source
    /// text. Offsets are Unicode-scalar indices, matching the Python
    /// `re.finditer` offsets GLiNER's decode reports.
    public struct Word: Equatable {
        public let text: String
        public let start: Int
        public let end: Int

        public init(text: String, start: Int, end: Int) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// GLiNER's word splitter: `\w+(?:[-_]\w+)*|\S` over the raw text
    /// (`gliner/data_processing/tokenizer.py`). A run of word
    /// characters (keeping internal hyphens/underscores) is one word;
    /// any other non-whitespace character is its own word — so
    /// "cathedral." splits into "cathedral" + ".".
    public static func splitWords(_ text: String) -> [Word] {
        // `\w` is Unicode-aware in ICU, matching Python 3's `re`.
        let pattern = #"\w+(?:[-_]\w+)*|\S"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let scalars = Array(text.unicodeScalars)
        var words: [Word] = []
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let start = text.unicodeScalars.distance(
                from: text.unicodeScalars.startIndex, to: range.lowerBound.samePosition(in: text.unicodeScalars)!
            )
            let end = text.unicodeScalars.distance(
                from: text.unicodeScalars.startIndex, to: range.upperBound.samePosition(in: text.unicodeScalars)!
            )
            words.append(Word(
                text: String(String.UnicodeScalarView(scalars[start..<end])),
                start: start,
                end: end
            ))
        }
        return words
    }

    /// `span_idx` — every candidate `(startWord, endWord)` pair. For
    /// each start word `s` in `0…wordCount-1` and width `w` in
    /// `0…maxSpanWidth-1`, the pair `[s, s + w]` (both inclusive).
    /// Row order: all widths of word 0, then word 1, … Length is
    /// `wordCount * maxSpanWidth`.
    public static func spanIndices(wordCount: Int) -> [[Int]] {
        var out: [[Int]] = []
        out.reserveCapacity(wordCount * maxSpanWidth)
        for s in 0..<max(0, wordCount) {
            for w in 0..<maxSpanWidth {
                out.append([s, s + w])
            }
        }
        return out
    }

    /// `span_mask` — one flag per `spanIndices` entry. A span is valid
    /// iff its end word is within the text: `s + w <= wordCount - 1`.
    public static func spanMask(wordCount: Int) -> [Bool] {
        var out: [Bool] = []
        out.reserveCapacity(wordCount * maxSpanWidth)
        for s in 0..<max(0, wordCount) {
            for w in 0..<maxSpanWidth {
                out.append(s + w <= wordCount - 1)
            }
        }
        return out
    }
}
