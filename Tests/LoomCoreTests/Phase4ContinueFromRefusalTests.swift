import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #7 / LOOM_NSFW.md §5 — "Continue from refusal" action.
///
/// When the model declines mid-generation, the History row chips the entry
/// yellow ("refusal?"). This phase adds a one-click "Push past refusal"
/// action on that row that:
///   1. Provides a refusal-breaking per-call instruction text (the
///      community technique: re-affirm fictional frame + forbid refusal).
///   2. Provides a continuation stub (the em-dash anchor that signals
///      the model to keep going from a hard break, per LOOM_NSFW §5).
///   3. Posts a notification the editor handles by inserting the stub
///      at cursor, loading the instruction into the tray, and the user
///      fires Continue from there.
///
/// The pure-data layer (instruction string + stub + notification name)
/// is TDD-tested here. The editor's notification handling is honest
/// smoke (covered by live use).
func phase4ContinueFromRefusalTests() -> TestSuite {
    let s = TestSuite("Phase4ContinueFromRefusal")

    // MARK: - Pure-data: instruction + stub

    s.test("RefusalContinuation.breakingInstruction re-affirms the fictional frame") {
        let text = RefusalContinuation.breakingInstruction
        try expectFalse(text.isEmpty)
        let lower = text.lowercased()
        // Must (a) forbid refusing, (b) tell the model to stay in the
        // narrative frame, (c) be authored as authorial direction not
        // chat-style apology.
        try expectTrue(
            lower.contains("do not refuse") || lower.contains("don't refuse"),
            "instruction must forbid refusal; got: \(text)"
        )
        try expectTrue(
            lower.contains("scene") || lower.contains("narrative") || lower.contains("fiction"),
            "instruction must reference the fictional/narrative frame; got: \(text)"
        )
        // No first-person apology shape — that's the refusal pattern we're
        // breaking, not echoing.
        try expectFalse(
            lower.contains("i'm sorry"),
            "instruction must not be in the apologetic voice it's countering"
        )
    }

    s.test("RefusalContinuation.continuationStub is the em-dash anchor") {
        // The community technique (LOOM_NSFW §5): a hard punctuation
        // break that signals the model to continue from a fresh
        // sentence, not echo the refusal.
        try expectEqual(RefusalContinuation.continuationStub, "—")
    }

    // MARK: - Notification surface

    s.test("HistoryInspectorViewController exposes a continue-from-refusal notification name") {
        // The History row posts this when the user clicks "Push past
        // refusal"; the editor observes and handles. Both sides
        // reference the same Notification.Name so the contract is
        // central.
        let name = HistoryInspectorViewController.requestContinueFromRefusalNotification
        try expectFalse(name.rawValue.isEmpty)
        try expectTrue(
            name.rawValue.contains("ContinueFromRefusal") ||
            name.rawValue.contains("PushPastRefusal"),
            "notification name should be self-describing; got: \(name.rawValue)"
        )
    }

    s.test("HistoryInspectorViewController.makeContinueFromRefusalUserInfo bundles stub + instruction") {
        // The userInfo dict the History row hands to the editor —
        // a single source of truth so the editor doesn't reach back
        // into the row for these strings.
        let info = HistoryInspectorViewController.makeContinueFromRefusalUserInfo()
        let stub = try expectNotNil(info["stub"] as? String)
        let instruction = try expectNotNil(info["instruction"] as? String)
        try expectEqual(stub, RefusalContinuation.continuationStub)
        try expectEqual(instruction, RefusalContinuation.breakingInstruction)
    }

    // MARK: - Row exposure (UI-shape contract, no AppKit needed)

    s.test("HistoryEntryRowView only surfaces push-past action when refusal was detected") {
        // The "Push past refusal" affordance must not appear on
        // ordinary entries — only refusal-flagged ones. Tested via
        // the row's static rendering predicate so we don't have to
        // drive AppKit.
        let entryRefusal = makeLogEntry(refusalDetected: true)
        let entryNormal = makeLogEntry(refusalDetected: false)
        try expectTrue(HistoryEntryRowView.shouldShowPushPastRefusal(entryRefusal))
        try expectFalse(HistoryEntryRowView.shouldShowPushPastRefusal(entryNormal))
    }

    return s
}

// MARK: - Helpers

private func makeLogEntry(refusalDetected: Bool) -> GenerationLogEntry {
    let assembly = PromptAssembly(
        contextChiclets: [],
        fullPrompt: "test prompt",
        promptTokens: 10,
        aboveCacheTokens: 5,
        belowCacheTokens: 5,
        evictedLayers: [],
        template: .raw
    )
    let response = GenerationResponse(
        rawText: refusalDetected ? "I cannot continue this scene." : "She walked into the room.",
        completionTokens: 5,
        stopReason: "stop_sequence",
        refusalDetected: refusalDetected,
        elapsedMs: 100
    )
    return GenerationLogEntry(
        id: UUID(),
        sceneId: UUID(),
        timestamp: Date(),
        mode: .continueProse,
        model: "test-model",
        serverProfileId: UUID(),
        promptAssembly: assembly,
        response: response
    )
}
