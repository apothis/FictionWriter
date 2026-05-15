import Foundation

/// Per-template wrapping for koboldcpp single-prompt completion.
/// Loom's PromptBuilder produces three logical pieces — `system` (the
/// stable above-cache content), `userBody` (the dynamic below-cache
/// content), and `prefill` (the assistant header tail; e.g. Qwen 3.x
/// suppresses default thinking via `<think>\n\n</think>\n\n`).
///
/// Each adapter wraps these three with the model-family special tokens.
/// For families without a native system role (Gemma 1/2/3, Mistral V3),
/// the system block is folded into the first user turn.
public protocol InstructTemplateAdapter {
    var id: InstructTemplate { get }
    var stopSequences: [String] { get }
    func wrap(system: String, userBody: String, prefill: String) -> String
}

public enum InstructTemplates {
    public static func adapter(for template: InstructTemplate) -> InstructTemplateAdapter {
        switch template {
        case .auto, .raw:           return RawAdapter()
        case .chatml:               return ChatMLAdapter()
        case .gemma3:               return Gemma3Adapter()
        case .gemma4:               return Gemma4Adapter()
        case .mistralV3:            return MistralV3Adapter()
        case .mistralV7:            return MistralV7Adapter()
        case .llama3:               return Llama3Adapter()
        case .alpaca:               return AlpacaAdapter()
        }
    }

    /// Best-effort detection from a `/api/v1/model` model-name string.
    /// Returns nil for unrecognised models — caller falls back to .raw
    /// rather than guessing wrong (the mismatch trap per
    /// LOOM_RESEARCH.md §I.4: a model finetuned on Alpaca degrades when
    /// prompted with ChatML, and vice versa).
    public static func detect(forModelName name: String) -> InstructTemplate? {
        let lower = name.lowercased()
        // Gemma 4 must be checked before "gemma" so the substring
        // doesn't fall through to the Gemma 1/2/3 family adapter.
        if lower.contains("gemma-4") || lower.contains("gemma4") {
            return .gemma4
        }
        if lower.contains("gemma") {
            return .gemma3
        }
        if lower.contains("qwen") {
            return .chatml
        }
        if lower.contains("llama-3") || lower.contains("llama3") {
            return .llama3
        }
        if lower.contains("mistral") || lower.contains("ministral") {
            // Mistral Large / Ministral / 2407+ era → V7 (native system).
            // Older 7B / Nemo era → V3 (system folded into first [INST]).
            if lower.contains("large")
                || lower.contains("ministral")
                || lower.contains("2407")
                || lower.contains("2410")
                || lower.contains("2411")
            {
                return .mistralV7
            }
            return .mistralV3
        }
        // Mistral-Small-3.x finetune family — filenames don't contain
        // "mistral" but all use V7 Tekken per their model cards.
        if lower.contains("cydonia") || lower.contains("goetia")
            || lower.contains("magidonia") || lower.contains("harbinger")
            || lower.contains("hearthfire") || lower.contains("skyfall")
        {
            return .mistralV7
        }
        return nil
    }
}

// MARK: - ChatML (Qwen 2.5 / 3.x and many merges)

struct ChatMLAdapter: InstructTemplateAdapter {
    var id: InstructTemplate { .chatml }
    var stopSequences: [String] { ["<|im_end|>", "<|im_start|>user"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        var out = ""
        if !system.isEmpty {
            out += "<|im_start|>system\n"
            out += system
            out += "<|im_end|>\n"
        }
        out += "<|im_start|>user\n"
        out += userBody
        out += "<|im_end|>\n"
        out += "<|im_start|>assistant\n"
        out += prefill
        return out
    }
}

// MARK: - Gemma 1/2/3 (no native system role)

struct Gemma3Adapter: InstructTemplateAdapter {
    var id: InstructTemplate { .gemma3 }
    var stopSequences: [String] { ["<end_of_turn>", "<start_of_turn>"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        // No native system lane in Gemma 1/2/3 — fold system into the
        // first user turn (RPClient pattern).
        let folded = system.isEmpty ? userBody : "\(system)\n\n\(userBody)"
        var out = ""
        out += "<start_of_turn>user\n"
        out += folded
        out += "<end_of_turn>\n"
        out += "<start_of_turn>model\n"
        out += prefill
        return out
    }
}

// MARK: - Gemma 4 (NEW — native system role; <|turn>...<turn|>)

struct Gemma4Adapter: InstructTemplateAdapter {
    var id: InstructTemplate { .gemma4 }
    /// Stop on `<turn|>` (closes any role's turn). Including `<|turn>`
    /// as a secondary safety net catches malformed completion that
    /// starts a fresh turn without closing the model's own.
    var stopSequences: [String] { ["<turn|>", "<|turn>"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        var out = ""
        if !system.isEmpty {
            out += "<|turn>system\n"
            out += system
            out += "<turn|>\n"
        }
        out += "<|turn>user\n"
        out += userBody
        out += "<turn|>\n"
        out += "<|turn>model\n"
        out += prefill
        return out
    }
}

// MARK: - Llama 3

struct Llama3Adapter: InstructTemplateAdapter {
    var id: InstructTemplate { .llama3 }
    var stopSequences: [String] { ["<|eot_id|>", "<|start_header_id|>"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        var out = ""
        if !system.isEmpty {
            out += "<|start_header_id|>system<|end_header_id|>\n\n"
            out += system
            out += "<|eot_id|>"
        }
        out += "<|start_header_id|>user<|end_header_id|>\n\n"
        out += userBody
        out += "<|eot_id|>"
        out += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        out += prefill
        return out
    }
}

// MARK: - Mistral V3 (Mistral 7B / Nemo era; no system role)

struct MistralV3Adapter: InstructTemplateAdapter {
    var id: InstructTemplate { .mistralV3 }
    var stopSequences: [String] { ["</s>", "[INST]"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        // Mistral V3: no [SYSTEM_PROMPT]. System content folds into the
        // [INST] block before the user message. Note the leading +
        // trailing single space inside [INST] — Mistral's tokenizer
        // expects this convention.
        let body: String = {
            if system.isEmpty { return userBody }
            return "\(system)\n\n\(userBody)"
        }()
        var out = ""
        out += "[INST] "
        out += body
        out += " [/INST]"
        out += prefill
        return out
    }
}

// MARK: - Mistral V7 (Mistral Large / Ministral 2407+; native system)

struct MistralV7Adapter: InstructTemplateAdapter {
    var id: InstructTemplate { .mistralV7 }
    var stopSequences: [String] { ["</s>", "[INST]"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        var out = ""
        if !system.isEmpty {
            out += "[SYSTEM_PROMPT]"
            out += system
            out += "[/SYSTEM_PROMPT]"
        }
        out += "[INST]"
        out += userBody
        out += "[/INST]"
        out += prefill
        return out
    }
}

// MARK: - Alpaca

struct AlpacaAdapter: InstructTemplateAdapter {
    var id: InstructTemplate { .alpaca }
    var stopSequences: [String] { ["### Instruction:", "### Response:"] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        var out = ""
        out += "### Instruction:\n"
        if system.isEmpty {
            out += userBody
        } else {
            out += "\(system)\n\n\(userBody)"
        }
        out += "\n\n### Response:\n"
        out += prefill
        return out
    }
}

// MARK: - Raw (no template; pure completion)

struct RawAdapter: InstructTemplateAdapter {
    var id: InstructTemplate { .raw }
    var stopSequences: [String] { [] }

    func wrap(system: String, userBody: String, prefill: String) -> String {
        // Pass everything through as plain text. Useful for base models
        // that never saw an instruct template, or when the user wants
        // explicit control over the wrap.
        var parts: [String] = []
        if !system.isEmpty { parts.append(system) }
        if !userBody.isEmpty { parts.append(userBody) }
        var out = parts.joined(separator: "\n\n")
        out += prefill
        return out
    }
}
