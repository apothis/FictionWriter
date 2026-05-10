import Foundation

/// Cheap rough token estimator. Used during prompt assembly for budget
/// math; the canonical token count comes from koboldcpp's
/// `/api/extra/tokencount` endpoint at submission time, but we can't
/// pay a network round-trip per layer per assembly. 4 chars/token is
/// the well-known approximation for English prose with current
/// instruct-tuned tokenizers (Qwen, Gemma, Llama-3 BPE families
/// converge around 3.5–4.5 chars/token; 4 is a safe central estimate).
public enum TokenEstimator {
    /// Estimate tokens. Empty string returns 0 (so layer accounting
    /// reflects the actual contribution).
    public static func estimate(_ s: String) -> Int {
        if s.isEmpty { return 0 }
        // Round-up so total estimate doesn't underflow a tight budget.
        return (s.count + 3) / 4
    }
}
