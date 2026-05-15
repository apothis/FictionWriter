import Foundation
@testable import LoomCore

/// Phase 8.b writer-model A/B — model-family sampler overrides.
/// Mistral-Small-3.x finetunes (Cydonia / Goetia / Magidonia /
/// Harbinger / Hearthfire / Skyfall) are temperature-sensitive and
/// want lower min_p / rep_pen than the Gemma-4 31B Deckard baseline
/// Loom is tuned for. The override applies at request-construction
/// time keyed off the probed model name, so an A/B between writer
/// models doesn't need per-project settings churn.
///
/// Reference: MuXodious Harbinger / Magidonia-heresy model cards
/// (temp 0.8, min_p 0.025, rep_pen 1.05); TheDrummer Cydonia-v2
/// discussion #4; Magidonia-v4.3 discussion #4.
func phase8SamplerFamilyOverrideTests() -> TestSuite {
    let s = TestSuite("Phase8SamplerFamilyOverride")

    s.test("unknown model → nil (no override; existing defaults apply)") {
        try expectNil(SamplerParams.familyOverride(forModelName: "some-random-model"))
        try expectNil(SamplerParams.familyOverride(forModelName: ""))
        try expectNil(SamplerParams.familyOverride(forModelName: nil))
    }

    s.test("Gemma-4 Deckard / Qwen / Llama → nil (no Mistral-Small override)") {
        // The current writer model + adjacent baselines must NOT trigger
        // the Mistral-Small override.
        try expectNil(SamplerParams.familyOverride(forModelName: "gemma-4-31B-it-The-DECKARD-HERETIC-UNCENSORED-Thinking.i1-Q4_K_M"))
        try expectNil(SamplerParams.familyOverride(forModelName: "Qwen3.6-27B-Heretic-Uncensored"))
        try expectNil(SamplerParams.familyOverride(forModelName: "Llama-3.1-8B-Instruct"))
    }

    s.test("Mistral-Small-3.x finetune family → temp=0.8 min_p=0.025 rep_pen=1.05") {
        let names = [
            "Goetia-24B-v1.3-absolute-heresy.i1-Q5_K_M.gguf",
            "Cydonia-24B-v4.3-absolute-heresy",
            "TheDrummer/Cydonia-24B-v4.3",
            "Magidonia-24B-v4.3",
            "TheDrummer/Skyfall-31B-v4.2",
            "Harbinger-24B-absolute-heresy",
            "Hearthfire-24B-absolute-heresy",
        ]
        for n in names {
            let ov = try expectNotNil(SamplerParams.familyOverride(forModelName: n))
            try expectEqual(ov.temperature, 0.8)
            try expectEqual(ov.minP, 0.025)
            try expectEqual(ov.repPen, 1.05)
        }
    }

    s.test("matching is case-insensitive") {
        _ = try expectNotNil(SamplerParams.familyOverride(forModelName: "GOETIA-24B-V1.3"))
        _ = try expectNotNil(SamplerParams.familyOverride(forModelName: "cydonia-24b-v4.3"))
    }

    return s
}
