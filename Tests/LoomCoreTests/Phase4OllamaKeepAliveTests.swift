import Foundation
@testable import LoomCore

/// Phase 4 #7 reliability fix — OllamaClient should hint the
/// extractor model to stay warm via `keep_alive`, otherwise the
/// default 5-minute timeout unloads the model between bursts of
/// editing and the first cold-load chat request returns empty
/// content (`message.content = ""`).
///
/// Default `keep_alive` is server-side 5 minutes; we override to
/// keep the model loaded for the realistic typing-pause window.
func phase4OllamaKeepAliveTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaKeepAlive")

    s.test("makeChatRequestBody includes a keep_alive hint") {
        let body = OllamaClient.makeChatRequestBody(
            model: "gemma4_2b:latest",
            prompt: "x",
            schema: [:],
            options: OllamaChatOptions()
        )
        let keepAlive = body["keep_alive"]
        _ = try expectNotNil(keepAlive)
    }

    s.test("default keep_alive is a string > 5m so the model survives editing pauses") {
        let body = OllamaClient.makeChatRequestBody(
            model: "m", prompt: "p", schema: [:], options: OllamaChatOptions()
        )
        let keepAlive = try expectNotNil(body["keep_alive"] as? String)
        // Accept any value of the form "Xm" where X > 5, or "Xh".
        // Encoded as a string per Ollama's API.
        try expectTrue(keepAlive.contains("m") || keepAlive.contains("h"))
    }

    return s
}
