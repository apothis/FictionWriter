import Foundation
@testable import LoomCore

/// Pure-data port of the Path E function-word z-score embedder from
/// `Tools/RagSpike/Python/embed_offline.py::embed_path_e`. Phase 5
/// production needs this Swift-side per LOOM_RAG_SPIKE §13.6 + §13.7
/// (hybrid D + E retrieval, where D is MLX-StyleDistance via Swift
/// MLXEmbedders and E is the 150-dim function-word baseline).
///
/// Behaviour pinned against the Python spec: tokenise as runs of
/// [a-z]+ after lowercasing; build vocabulary as the top-N tokens by
/// global frequency with tie-break by first-encountered insertion
/// order (matches `collections.Counter.most_common`); per-text vector
/// = z-score of relative frequency over the top-N vocabulary, where
/// "relative frequency" is `local_count / sum_of_top_N_local_counts`
/// (NOT `local_count / len(tokens)` — off-vocab tokens reduce all
/// rel-freq denominators uniformly); z-score uses population std
/// (ddof=0) with a < 1e-9 guard that clamps std=1.
func phase5FuncwordZTests() -> TestSuite {
    let s = TestSuite("Phase5FuncwordZ")

    // MARK: - Tokenisation

    s.test("tokenize lowercases and splits on non-letter runs") {
        let toks = FuncwordZEmbedder.tokenize("Hello, World! How are you?")
        try expectEqual(toks, ["hello", "world", "how", "are", "you"])
    }

    s.test("tokenize on empty string returns empty array") {
        try expectEqual(FuncwordZEmbedder.tokenize(""), [])
    }

    s.test("tokenize discards digits, punctuation, and apostrophes") {
        // Python's WORD_RE = r"[a-z]+" — "don't" becomes ["don", "t"]
        // because apostrophe is not in [a-z]. Pin that behaviour.
        let toks = FuncwordZEmbedder.tokenize("It's 2026 — don't forget.")
        try expectEqual(toks, ["it", "s", "don", "t", "forget"])
    }

    s.test("tokenize collapses repeated whitespace + newlines") {
        let toks = FuncwordZEmbedder.tokenize("alpha\n\nbeta   gamma\tdelta")
        try expectEqual(toks, ["alpha", "beta", "gamma", "delta"])
    }

    // MARK: - fit: vocabulary construction

    s.test("fit picks the top-N tokens by frequency") {
        let corpus = [
            "the the the the",
            "the the cat cat",
            "the dog",
        ]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 2)
        try expectEqual(model.vocabulary, ["the", "cat"])
    }

    s.test("fit ties broken by first-encountered order (matches Python Counter.most_common)") {
        // a + b + c each appear once; vocabulary order = encounter order = a, b, c
        let corpus = ["a b", "c"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 3)
        try expectEqual(model.vocabulary, ["a", "b", "c"])
    }

    s.test("fit topN larger than vocabulary keeps all unique tokens") {
        let corpus = ["a a b"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 150)
        try expectEqual(Set(model.vocabulary), Set(["a", "b"]))
    }

    // MARK: - fit + transform: hand-computed symmetric corpus

    s.test("fit + transform reproduces hand-computed z-scores on a symmetric corpus") {
        // corpus = ["a a b", "a c c", "b b c"], top_n=3
        // tokens: t0=[a,a,b], t1=[a,c,c], t2=[b,b,c]
        // counts all-tied at 3 — vocab in encounter order: [a, b, c]
        //
        // per-text rel-freq over [a,b,c]:
        //   t0: [2/3, 1/3, 0]
        //   t1: [1/3, 0, 2/3]
        //   t2: [0, 2/3, 1/3]
        //
        // per-dim mean: [1/3, 1/3, 1/3]
        // per-dim variance (ddof=0): 2/27 for every dim
        // per-dim std: sqrt(2/27) ≈ 0.27216552697
        //
        // z-scores:
        //   t0: [+1.22474, 0, -1.22474]
        //   t1: [0, -1.22474, +1.22474]
        //   t2: [-1.22474, +1.22474, 0]
        let corpus = ["a a b", "a c c", "b b c"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 3)
        try expectEqual(model.vocabulary, ["a", "b", "c"])

        let z0 = FuncwordZEmbedder.transform(corpus[0], using: model)
        let z1 = FuncwordZEmbedder.transform(corpus[1], using: model)
        let z2 = FuncwordZEmbedder.transform(corpus[2], using: model)

        let tol: Float = 1e-4
        let expected: Float = 1.2247448713915892
        try expectTrue(abs(z0.values[0] - expected) < tol, "z0[0]=\(z0.values[0])")
        try expectTrue(abs(z0.values[1] - 0) < tol, "z0[1]=\(z0.values[1])")
        try expectTrue(abs(z0.values[2] + expected) < tol, "z0[2]=\(z0.values[2])")

        try expectTrue(abs(z1.values[0] - 0) < tol)
        try expectTrue(abs(z1.values[1] + expected) < tol)
        try expectTrue(abs(z1.values[2] - expected) < tol)

        try expectTrue(abs(z2.values[0] + expected) < tol)
        try expectTrue(abs(z2.values[1] - expected) < tol)
        try expectTrue(abs(z2.values[2] - 0) < tol)
    }

    s.test("transform produces vectors with dim == model.dim") {
        let model = FuncwordZEmbedder.fit(corpus: ["a b c d e"], topN: 3)
        let v = FuncwordZEmbedder.transform("a x y z", using: model)
        try expectEqual(v.dim, model.dim)
        try expectEqual(v.dim, 3)
    }

    // MARK: - Edge cases

    s.test("transform on empty text uses (0 - mean)/std for every dim") {
        // Python's `or 1` guard: total=0 → fallback 1; rel stays all
        // zeros. So z = (0 - mean) / std per dim.
        let corpus = ["a a b", "a c c", "b b c"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 3)
        let zEmpty = FuncwordZEmbedder.transform("", using: model)
        for j in 0..<model.dim {
            let expected = -model.mean[j] / model.std[j]
            try expectTrue(
                abs(zEmpty.values[j] - expected) < 1e-4,
                "dim \(j): got \(zEmpty.values[j]), expected \(expected)"
            )
        }
    }

    s.test("transform on text with no in-vocab tokens uses (0 - mean)/std") {
        let corpus = ["a a b", "a c c", "b b c"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 3)
        let z = FuncwordZEmbedder.transform("zzz qqq vvv", using: model)
        for j in 0..<model.dim {
            let expected = -model.mean[j] / model.std[j]
            try expectTrue(abs(z.values[j] - expected) < 1e-4)
        }
    }

    s.test("std=0 guard: corpus of identical texts produces zero z-scores, not NaN") {
        // All texts identical → per-dim rel-freq is the same across
        // the corpus → variance 0. The < 1e-9 guard clamps std=1; the
        // resulting z-score is (rel - mean)/1 = 0.
        let corpus = ["the cat sat", "the cat sat"]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 3)
        let z = FuncwordZEmbedder.transform(corpus[0], using: model)
        for v in z.values {
            try expectTrue(v.isFinite, "got non-finite \(v)")
            try expectTrue(abs(v) < 1e-5, "expected ~0, got \(v)")
        }
    }

    s.test("a text matching one from the fit corpus reproduces that corpus row's z-score") {
        // Internal consistency: fit(corpus); then transform(corpus[i])
        // must match the i-th row of fit's internal rel-freq -> z
        // computation. This catches off-by-one in the topN restriction
        // and mean/std caching bugs.
        let corpus = [
            "the the cat sat on the mat",
            "the dog ran fast on the road",
            "the bird flew over the tree",
        ]
        let model = FuncwordZEmbedder.fit(corpus: corpus, topN: 5)
        let z0 = FuncwordZEmbedder.transform(corpus[0], using: model)
        let z1 = FuncwordZEmbedder.transform(corpus[1], using: model)
        let z2 = FuncwordZEmbedder.transform(corpus[2], using: model)
        // Internal-consistency invariant: the mean across the corpus
        // of each dim's z-score is ~0 (modulo float rounding).
        for j in 0..<model.dim {
            let m = (z0.values[j] + z1.values[j] + z2.values[j]) / 3.0
            try expectTrue(abs(m) < 1e-4, "dim \(j) mean of z-scores = \(m); should be ~0")
        }
    }

    return s
}
