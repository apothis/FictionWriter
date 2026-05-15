import Foundation
@testable import LoomCore

/// Sub-step 1.i.A — instruct-template adapters. Pure: each template
/// wraps a (system, user, prefill) triple with the model-specific
/// special tokens; auto-detection from a model-name string picks the
/// right template family. ChatML / Gemma3 / Gemma4 / Llama3 / Mistral
/// V3 / Mistral V7 / Alpaca / Raw — eight in total.
///
/// Reference templates verified 2026-05-10 against:
///   - Qwen 3.6 (ChatML; <|im_start|> single-token; <think>\n\n</think>
///     prefill suppresses default thinking mode for story prose)
///   - Gemma 4 (new <|turn>...<turn|> with NATIVE system role; differs
///     from Gemma 1/2/3's <start_of_turn>...<end_of_turn> family which
///     has no native system role)
///   - llama.cpp + koboldcpp template registries
///   - Unsloth chat-templates docs
func phase1InstructTemplateTests() -> TestSuite {
    let s = TestSuite("Phase1InstructTemplate")

    // MARK: - Per-template wrapping

    s.test("ChatML wraps system+user with <|im_start|>...<|im_end|>") {
        let t = InstructTemplates.adapter(for: .chatml)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        try expectTrue(out.contains("<|im_start|>system\nsystem text<|im_end|>"))
        try expectTrue(out.contains("<|im_start|>user\nuser text<|im_end|>"))
        try expectTrue(out.hasSuffix("<|im_start|>assistant\n"))
    }

    s.test("ChatML preserves prefill (used to suppress Qwen 3.x think-mode)") {
        let t = InstructTemplates.adapter(for: .chatml)
        let prefill = "<think>\n\n</think>\n\n"
        let out = t.wrap(system: "S", userBody: "U", prefill: prefill)
        try expectTrue(out.hasSuffix("<|im_start|>assistant\n" + prefill))
    }

    s.test("Gemma3 has no system role — system folds into first user") {
        let t = InstructTemplates.adapter(for: .gemma3)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        // Gemma 1/2/3 has no <start_of_turn>system — the system content
        // gets prepended to the first user turn.
        try expectFalse(out.contains("<start_of_turn>system"))
        try expectTrue(out.contains("<start_of_turn>user\nsystem text\n\nuser text<end_of_turn>"))
        try expectTrue(out.hasSuffix("<start_of_turn>model\n"))
    }

    s.test("Gemma4 uses new <|turn>...<turn|> with NATIVE system role") {
        // Gemma 4's headline change vs Gemma 1/2/3: native system role.
        let t = InstructTemplates.adapter(for: .gemma4)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        try expectTrue(out.contains("<|turn>system\nsystem text<turn|>"))
        try expectTrue(out.contains("<|turn>user\nuser text<turn|>"))
        try expectTrue(out.hasSuffix("<|turn>model\n"))
    }

    s.test("Llama3 uses <|start_header_id|>...<|end_header_id|> + <|eot_id|>") {
        let t = InstructTemplates.adapter(for: .llama3)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        try expectTrue(out.contains("<|start_header_id|>system<|end_header_id|>\n\nsystem text<|eot_id|>"))
        try expectTrue(out.contains("<|start_header_id|>user<|end_header_id|>\n\nuser text<|eot_id|>"))
        try expectTrue(out.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"))
    }

    s.test("Mistral V3 has no system role — folds into first [INST]") {
        let t = InstructTemplates.adapter(for: .mistralV3)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        // V3: system collapsed into the [INST] block; no [SYSTEM_PROMPT].
        try expectFalse(out.contains("[SYSTEM_PROMPT]"))
        try expectTrue(out.contains("[INST] system text\n\nuser text [/INST]"))
    }

    s.test("Mistral V7 uses [SYSTEM_PROMPT]...[/SYSTEM_PROMPT] before [INST]") {
        let t = InstructTemplates.adapter(for: .mistralV7)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        try expectTrue(out.contains("[SYSTEM_PROMPT]system text[/SYSTEM_PROMPT]"))
        try expectTrue(out.contains("[INST]user text[/INST]"))
    }

    s.test("Alpaca uses ### Instruction: / ### Response:") {
        let t = InstructTemplates.adapter(for: .alpaca)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "")
        try expectTrue(out.contains("### Instruction:\nsystem text\n\nuser text"))
        try expectTrue(out.contains("### Response:\n"))
    }

    s.test("Raw passes through with system+user concatenated, no special tokens") {
        let t = InstructTemplates.adapter(for: .raw)
        let out = t.wrap(system: "system text", userBody: "user text", prefill: "prefill")
        try expectFalse(out.contains("<|im_start|>"))
        try expectFalse(out.contains("<start_of_turn>"))
        try expectFalse(out.contains("[INST]"))
        try expectTrue(out.contains("system text"))
        try expectTrue(out.contains("user text"))
        try expectTrue(out.hasSuffix("prefill"))
    }

    // MARK: - Stop sequences

    s.test("ChatML stop sequence is <|im_end|>") {
        let t = InstructTemplates.adapter(for: .chatml)
        try expectTrue(t.stopSequences.contains("<|im_end|>"))
    }

    s.test("Gemma3 stop sequence is <end_of_turn>") {
        let t = InstructTemplates.adapter(for: .gemma3)
        try expectTrue(t.stopSequences.contains("<end_of_turn>"))
    }

    s.test("Gemma4 stop sequence is <turn|>") {
        let t = InstructTemplates.adapter(for: .gemma4)
        try expectTrue(t.stopSequences.contains("<turn|>"))
    }

    s.test("Llama3 stop sequence is <|eot_id|>") {
        let t = InstructTemplates.adapter(for: .llama3)
        try expectTrue(t.stopSequences.contains("<|eot_id|>"))
    }

    // MARK: - Auto-detection from model name

    s.test("auto-detect: 'qwen3-30B-instruct' → chatml") {
        try expectEqual(InstructTemplates.detect(forModelName: "qwen3-30B-instruct"), .chatml)
        try expectEqual(InstructTemplates.detect(forModelName: "Qwen3-72B"), .chatml)
        try expectEqual(InstructTemplates.detect(forModelName: "qwen2.5-7b"), .chatml)
    }

    s.test("auto-detect: 'gemma-4' / 'gemma4' → gemma4 (preferred over gemma3)") {
        try expectEqual(InstructTemplates.detect(forModelName: "google/gemma-4-E4B-it"), .gemma4)
        try expectEqual(InstructTemplates.detect(forModelName: "Huihui-Gemma4-31B"), .gemma4)
    }

    s.test("auto-detect: 'gemma' (no '-4') → gemma3 family") {
        try expectEqual(InstructTemplates.detect(forModelName: "gemma-3-27B"), .gemma3)
        try expectEqual(InstructTemplates.detect(forModelName: "gemma-2-9B"), .gemma3)
        try expectEqual(InstructTemplates.detect(forModelName: "gemma-7B"), .gemma3)
    }

    s.test("auto-detect: 'llama-3' → llama3") {
        try expectEqual(InstructTemplates.detect(forModelName: "Llama-3.1-8B-Instruct"), .llama3)
        try expectEqual(InstructTemplates.detect(forModelName: "meta-llama-3-70b"), .llama3)
    }

    s.test("auto-detect: 'mistral' Large/Nemo → mistralV7; older → mistralV3") {
        // Mistral Large / Ministral / 2407+ era favours V7; pre-2024
        // Mistral 7B Instruct + Nemo finetunes use V3.
        try expectEqual(InstructTemplates.detect(forModelName: "mistral-large-2407"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Ministral-8B-Instruct-2410"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Mistral-Nemo-Instruct"), .mistralV3)
        try expectEqual(InstructTemplates.detect(forModelName: "mistral-7b-instruct-v0.2"), .mistralV3)
    }

    s.test("auto-detect: Mistral-Small-24B finetune family → mistralV7") {
        // Drummer / MuXodious / Naphula / LatitudeGames finetunes of
        // Mistral-Small-3.x — none contain "mistral" in their filename,
        // but all use Mistral v7 Tekken format per their model cards.
        try expectEqual(InstructTemplates.detect(forModelName: "Goetia-24B-v1.3-absolute-heresy.i1-Q5_K_M.gguf"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Cydonia-24B-v4.3-absolute-heresy"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "TheDrummer/Cydonia-24B-v4.3"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Magidonia-24B-v4.3"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "TheDrummer/Skyfall-31B-v4.2"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Harbinger-24B-absolute-heresy"), .mistralV7)
        try expectEqual(InstructTemplates.detect(forModelName: "Hearthfire-24B-absolute-heresy"), .mistralV7)
    }

    s.test("auto-detect: unknown → nil (caller falls back to .raw)") {
        try expectNil(InstructTemplates.detect(forModelName: "some-random-model"))
        try expectNil(InstructTemplates.detect(forModelName: ""))
    }

    return s
}
