import Foundation

/// Formats retrieved [`StyleExemplar`](../Retrieval/RetrievalService.swift)
/// values into a prompt block for the writer-LLM. Phase 5 production
/// integration of the hybrid retrieval pipeline into [`PromptBuilder`](PromptBuilder.swift).
///
/// Block shape:
///
///     [STYLE EXEMPLARS]
///     Use the following passages as voice/style cues for your prose.
///     Do NOT quote, copy, or paraphrase their content — match their
///     rhythm, sentence length, and register only.
///
///     — from "Hemingway sample" (action):
///     He walked the road. The road was long.
///
///     — from "lush gothic excerpt" (description):
///     The corridors stretched away in shadow, and the wax of the
///     candles ran slow upon the floor...
///     [END]
///
/// Framing rationale per [LOOM_RAG_SPIKE.md §13.3(d)](../../LOOM_RAG_SPIKE.md):
/// retrieved chunks share *style* with the query but may share
/// *content* (NSFW-vocabulary clustering, topic-overlap, etc). Without
/// the explicit "voice cues, not content" instruction, generation
/// risks plagiarising the exemplar text.
public enum StyleExemplarsLayer {
    /// Returns the empty string when no exemplars are provided —
    /// callers (PromptBuilder) check for empty and skip the layer.
    public static func format(_ exemplars: [StyleExemplar]) -> String {
        guard !exemplars.isEmpty else { return "" }

        var out = "[STYLE EXEMPLARS]\n"
        out += "Use the following passages as voice and style cues for your prose. "
        out += "Do NOT quote, copy, or paraphrase their content — match their rhythm, "
        out += "sentence length, and register only.\n"

        for ex in exemplars {
            out += "\n"
            let modalityTag = ex.modality.map { " (\($0.rawValue))" } ?? ""
            out += "— from \"\(ex.referenceName)\"\(modalityTag):\n"
            out += ex.text
            out += "\n"
        }

        out += "[END]"
        return out
    }
}
