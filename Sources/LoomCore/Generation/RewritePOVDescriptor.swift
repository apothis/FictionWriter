import Foundation

/// Phase 4 §14.1 #8 — pure-data formatter for the rewritePOV
/// descriptor that lands on `PromptContext.perCallInstruction`.
/// Format mirrors the `[KNOWLEDGE-LEDGER]` prompt layer (sub-task 7
/// / LOOM_GENERATION_MODES.md §11): leading target-POV line, then a
/// KNOWS bullet list, then a DOES NOT KNOW bullet list. Empty
/// buckets omit their sub-block; both empty produces just the
/// target-POV line.
///
/// Default treatment is third-person limited — most common in
/// modern fiction. Power users override via the tray instruction
/// field at call time (typing "first-person, limited" or similar
/// into the field amplifies the descriptor through the existing
/// per-call layer in `PromptBuilder.systemPromptFor(...)`).
public enum RewritePOVDescriptor {
    public static func build(
        targetName: String,
        knowledge: LedgerKnowledge.Result
    ) -> String {
        var lines: [String] = []
        lines.append("Target POV: \(targetName) (third-person, limited).")

        if !knowledge.knows.isEmpty {
            lines.append("")
            lines.append("\(targetName) KNOWS as of this scene:")
            for fact in knowledge.knows {
                lines.append("- \(fact.fact)")
            }
        }

        if !knowledge.unknowns.isEmpty {
            lines.append("")
            lines.append("\(targetName) does NOT know:")
            for fact in knowledge.unknowns {
                lines.append("- \(fact.fact)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
