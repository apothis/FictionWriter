import Foundation

/// Function-word z-score embedder — Path E from
/// [LOOM_RAG_SPIKE.md §13](../../LOOM_RAG_SPIKE.md), Swift port of
/// `Tools/RagSpike/Python/embed_offline.py::embed_path_e` per
/// Phase 5 production scope-lock #2.
///
/// Algorithm (matching the Python spec exactly):
///
/// 1. **Tokenise** each text as runs of `[a-z]+` after lowercasing.
///    Non-letters (digits, punctuation, apostrophes, whitespace) are
///    separators; *not* part of any token.
/// 2. **Vocabulary**: the top-N tokens by global frequency across the
///    fit corpus, with tie-break by first-encountered insertion order
///    (matches `collections.Counter.most_common`).
/// 3. **Per-text relative frequency** over the vocabulary:
///    `rel[i, j] = local_count(vocab[j]) / sum_of_top_N_local_counts`.
///    Off-vocab tokens are excluded from the denominator. Texts with
///    no in-vocab tokens get an all-zero rel-freq vector.
/// 4. **z-score per dim** using corpus mean + population std (ddof=0).
///    A `< 1e-9` std guard clamps std=1 to avoid divide-by-zero on
///    degenerate corpora.
///
/// Production-shape fit/transform API: build a `FuncwordZModel` once
/// over the reference corpus, then transform query strings against
/// that fitted model. This matches the eventual Phase 5 deployment
/// where the model fits on ingest-time reference texts and queries
/// transform at retrieval time.

public struct FuncwordZModel: Equatable {
    public let vocabulary: [String]
    public let mean: [Float]
    public let std: [Float]
    public var dim: Int { vocabulary.count }

    public init(vocabulary: [String], mean: [Float], std: [Float]) {
        self.vocabulary = vocabulary
        self.mean = mean
        self.std = std
    }
}

public enum FuncwordZEmbedder {
    /// Lowercase + [a-z]+ token runs. Mirrors Python's `re.findall(r"[a-z]+", text.lower())`.
    public static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text.lowercased() {
            // [a-z]+ — ASCII lowercase letters only, not Unicode letters
            // (matches Python's r"[a-z]+" literal class).
            if let scalar = ch.unicodeScalars.first,
               scalar.value >= 0x61 && scalar.value <= 0x7A,
               ch.unicodeScalars.count == 1 {
                current.append(ch)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    public static func fit(corpus: [String], topN: Int = 150) -> FuncwordZModel {
        let tokenLists = corpus.map { tokenize($0) }

        // Global token counts with insertion-order tracking for
        // deterministic tie-break (matches Python Counter behaviour).
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var insertionCounter = 0
        for tokens in tokenLists {
            for t in tokens {
                if counts[t] == nil {
                    firstSeen[t] = insertionCounter
                    insertionCounter += 1
                }
                counts[t, default: 0] += 1
            }
        }

        // Top-N by (count desc, firstSeen asc).
        let vocabulary = Array(
            counts.keys.sorted { lhs, rhs in
                let la = counts[lhs] ?? 0
                let lb = counts[rhs] ?? 0
                if la != lb { return la > lb }
                return (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0)
            }.prefix(topN)
        )

        let n = vocabulary.count
        let vocabIndex = Dictionary(
            uniqueKeysWithValues: vocabulary.enumerated().map { ($0.element, $0.offset) }
        )

        // Per-text rel-freq matrix
        let relFreqs: [[Float]] = tokenLists.map { tokens in
            var local = [Int](repeating: 0, count: n)
            var topNTotal = 0
            for t in tokens {
                if let idx = vocabIndex[t] {
                    local[idx] += 1
                    topNTotal += 1
                }
            }
            let total = topNTotal == 0 ? 1 : topNTotal
            return local.map { Float($0) / Float(total) }
        }

        let C = Float(max(corpus.count, 1))
        var mean = [Float](repeating: 0, count: n)
        for r in relFreqs {
            for j in 0..<n { mean[j] += r[j] }
        }
        for j in 0..<n { mean[j] /= C }

        // Population std (ddof=0), guarded.
        var std = [Float](repeating: 0, count: n)
        for r in relFreqs {
            for j in 0..<n {
                let d = r[j] - mean[j]
                std[j] += d * d
            }
        }
        for j in 0..<n {
            std[j] = (std[j] / C).squareRoot()
            if std[j] < 1e-9 { std[j] = 1 }
        }

        return FuncwordZModel(vocabulary: vocabulary, mean: mean, std: std)
    }

    public static func transform(_ text: String, using model: FuncwordZModel) -> EmbeddingVector {
        let tokens = tokenize(text)
        let n = model.dim
        let vocabIndex = Dictionary(
            uniqueKeysWithValues: model.vocabulary.enumerated().map { ($0.element, $0.offset) }
        )

        var local = [Int](repeating: 0, count: n)
        var topNTotal = 0
        for t in tokens {
            if let idx = vocabIndex[t] {
                local[idx] += 1
                topNTotal += 1
            }
        }
        let total = topNTotal == 0 ? 1 : topNTotal

        var z = [Float](repeating: 0, count: n)
        for j in 0..<n {
            let rel = Float(local[j]) / Float(total)
            z[j] = (rel - model.mean[j]) / model.std[j]
        }
        return EmbeddingVector(values: z)
    }
}
