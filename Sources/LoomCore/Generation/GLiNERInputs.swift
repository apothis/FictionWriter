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

    /// DeBERTa-v3 / GLiNER special token ids. `[CLS]`/`[SEP]` wrap the
    /// whole sequence; `<<ENT>>`/`<<SEP>>` delimit the label prompt
    /// region. From the exported tokenizer config + `added_tokens.json`.
    public static let clsToken = 1
    public static let sepToken = 2
    public static let entToken = 128002
    public static let promptSepToken = 128003

    /// The six per-call tensors GLiNER's ONNX graph reads, minus the
    /// span tensors (`spanIndices` / `spanMask`, built separately).
    /// `textLength` is the word count GLiNER feeds as `text_lengths`.
    public struct ModelInputs: Equatable {
        public let inputIDs: [Int]
        public let attentionMask: [Int]
        public let wordsMask: [Int]
        public let textLength: Int

        public init(inputIDs: [Int], attentionMask: [Int], wordsMask: [Int], textLength: Int) {
            self.inputIDs = inputIDs
            self.attentionMask = attentionMask
            self.wordsMask = wordsMask
            self.textLength = textLength
        }
    }

    /// Assemble GLiNER's input sequence from per-word subword ids.
    ///
    /// Layout (`gliner/data_processing/processor.py`):
    /// `[CLS] (<<ENT>> label)* <<SEP>> word* [SEP]`. Each label and each
    /// text word is tokenised independently (`is_split_into_words`); the
    /// caller passes the resulting subword-id arrays.
    ///
    /// `words_mask` carries the first subword of text word *i* its
    /// 1-based index; `[CLS]`/`[SEP]`, the whole label-prompt region,
    /// and continuation subwords are 0 — the mask the model uses to
    /// gather per-word representations.
    public static func assembleSequence(
        labelSubwords: [[Int]],
        wordSubwords: [[Int]]
    ) -> ModelInputs {
        var inputIDs: [Int] = [clsToken]
        var wordsMask: [Int] = [0]

        for label in labelSubwords {
            inputIDs.append(entToken)
            wordsMask.append(0)
            inputIDs.append(contentsOf: label)
            wordsMask.append(contentsOf: Array(repeating: 0, count: label.count))
        }
        inputIDs.append(promptSepToken)
        wordsMask.append(0)

        for (index, word) in wordSubwords.enumerated() {
            inputIDs.append(contentsOf: word)
            wordsMask.append(index + 1)
            wordsMask.append(contentsOf: Array(repeating: 0, count: max(0, word.count - 1)))
        }

        inputIDs.append(sepToken)
        wordsMask.append(0)

        return ModelInputs(
            inputIDs: inputIDs,
            attentionMask: Array(repeating: 1, count: inputIDs.count),
            wordsMask: wordsMask,
            textLength: wordSubwords.count
        )
    }

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

    /// Split `words` into windows of at most `maxWords`, broken at
    /// sentence boundaries.
    ///
    /// GLiNER's `max_len` is 384 words; a scene longer than that must
    /// be processed in chunks. Windowing at sentence boundaries means
    /// no entity (always within a sentence) is split across a window
    /// edge, so per-window detection results simply concatenate — no
    /// boundary dedup needed. A single sentence longer than `maxWords`
    /// is hard-split as a last resort.
    public static func wordWindows(words: [Word], maxWords: Int) -> [[Word]] {
        guard words.count > maxWords, maxWords > 0 else { return words.isEmpty ? [] : [words] }

        // A terminator word (the splitter emits punctuation as its own
        // word) ends a sentence.
        let terminators: Set<String> = [".", "!", "?"]
        var sentences: [[Word]] = []
        var sentence: [Word] = []
        for word in words {
            sentence.append(word)
            if terminators.contains(word.text) {
                sentences.append(sentence)
                sentence = []
            }
        }
        if !sentence.isEmpty { sentences.append(sentence) }

        var windows: [[Word]] = []
        var window: [Word] = []
        for sentence in sentences {
            if !window.isEmpty, window.count + sentence.count > maxWords {
                windows.append(window)
                window = []
            }
            if sentence.count > maxWords {
                if !window.isEmpty { windows.append(window); window = [] }
                var i = 0
                while i < sentence.count {
                    windows.append(Array(sentence[i..<min(i + maxWords, sentence.count)]))
                    i += maxWords
                }
            } else {
                window.append(contentsOf: sentence)
            }
        }
        if !window.isEmpty { windows.append(window) }
        return windows
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
