import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 1 — `OllamaClient` is the role-routed extractor
/// transport, lifted out of the spike's free-function shape in
/// `Tools/LedgerSpike/main.swift`. Pins the wire shape: POST /api/chat
/// with `{ model, messages, stream: false, options, format: <schema> }`,
/// response message.content carrying the JSON-Schema-constrained
/// extraction. Pure-data tests cover the request-body builder + the
/// response parser; the live extract() method is honest smoke.
///
/// Why /api/chat (not /api/generate): Gemma 4 needs its
/// `<start_of_turn>user/model` chat template applied, and Ollama's
/// /api/chat does that server-side from the model's metadata.
func phase4OllamaClientTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaClient")

    s.test("makeChatRequestBody emits model + messages + stream:true + format schema") {
        let schema: [String: Any] = ["type": "array"]
        let body = OllamaClient.makeChatRequestBody(
            model: "gemma4_2b:latest",
            prompt: "Extract facts.",
            schema: schema,
            options: OllamaChatOptions()
        )

        try expectEqual(body["model"] as? String, "gemma4_2b:latest")
        // Streaming — dodges Ollama's non-streaming empty-content bug
        // with gemma4 (verified live 2026-05-16).
        try expectEqual(body["stream"] as? Bool, true)

        let messages = try expectNotNil(body["messages"] as? [[String: String]])
        try expectEqual(messages.count, 1)
        try expectEqual(messages[0]["role"], "user")
        try expectEqual(messages[0]["content"], "Extract facts.")

        let format = try expectNotNil(body["format"] as? [String: Any])
        try expectEqual(format["type"] as? String, "array")
    }

    s.test("makeChatRequestBody omits format when the schema is empty") {
        // Empty schema = unconstrained generation. Ollama's
        // format-constrained mode flakes into an empty-content
        // degenerate loop (verified live 2026-05-16) — entity- and
        // relationship-discovery opt out by passing [:].
        let body = OllamaClient.makeChatRequestBody(
            model: "m", prompt: "p", schema: [:], options: OllamaChatOptions()
        )
        try expectTrue(body["format"] == nil, "empty schema must not emit a format key")
    }

    s.test("makeChatRequestBody includes options dict with extraction-tuned defaults") {
        let body = OllamaClient.makeChatRequestBody(
            model: "gemma4_2b:latest",
            prompt: "p",
            schema: [:],
            options: OllamaChatOptions()  // defaults: temp 0.3, num_predict 2048, repeat_penalty 1.1
        )
        let options = try expectNotNil(body["options"] as? [String: Any])
        try expectEqual(options["temperature"] as? Double, 0.3)
        // 2048 (not 1024): Ollama's JSON-Schema mode emits empty
        // content when num_predict cuts off before the schema
        // accepts a valid completion. The §11/§12 spike's 1024 was
        // tuned to ~150-word fixture scenes; production scenes
        // routinely need ~1600 tokens, so 2048 is the new safe
        // floor. Confirmed live 2026-05-12.
        try expectEqual(options["num_predict"] as? Int, 2048)
        try expectEqual(options["repeat_penalty"] as? Double, 1.1)
    }

    s.test("makeChatRequestBody honours overridden options") {
        let opts = OllamaChatOptions(temperature: 0.7, numPredict: 2048, repeatPenalty: 1.05)
        let body = OllamaClient.makeChatRequestBody(model: "m", prompt: "p", schema: [:], options: opts)
        let options = try expectNotNil(body["options"] as? [String: Any])
        try expectEqual(options["temperature"] as? Double, 0.7)
        try expectEqual(options["num_predict"] as? Int, 2048)
        try expectEqual(options["repeat_penalty"] as? Double, 1.05)
    }

    s.test("parseChatResponseContent extracts message.content from a well-formed Ollama response") {
        let json = """
        {
          "model": "gemma4_2b:latest",
          "message": {"role": "assistant", "content": "[{\\"fact\\":\\"x\\"}]"},
          "done": true
        }
        """
        let content = try OllamaClient.parseChatResponseContent(from: Data(json.utf8))
        try expectEqual(content, "[{\"fact\":\"x\"}]")
    }

    s.test("parseChatResponseContent concatenates a streaming (newline-delimited) body") {
        let body = """
        {"model":"m","message":{"role":"assistant","content":"char"},"done":false}
        {"model":"m","message":{"role":"assistant","content":"acter | "},"done":false}
        {"model":"m","message":{"role":"assistant","content":"Mia | q"},"done":false}
        {"model":"m","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}
        """
        let content = try OllamaClient.parseChatResponseContent(from: Data(body.utf8))
        try expectEqual(content, "character | Mia | q")
    }

    s.test("parseChatResponseContent throws unexpectedShape when message field is missing") {
        let json = """
        { "model": "m", "done": true }
        """
        do {
            _ = try OllamaClient.parseChatResponseContent(from: Data(json.utf8))
            try expectTrue(false, "expected throw")
        } catch let e as OllamaError {
            try expectEqual(e, .unexpectedShape)
        } catch {
            try expectTrue(false, "wrong error: \(error)")
        }
    }

    s.test("parseChatResponseContent throws unexpectedShape on non-JSON garbage") {
        do {
            _ = try OllamaClient.parseChatResponseContent(from: Data("not json".utf8))
            try expectTrue(false, "expected throw")
        } catch let e as OllamaError {
            try expectEqual(e, .unexpectedShape)
        } catch {
            try expectTrue(false, "wrong error: \(error)")
        }
    }

    s.test("OllamaClient resolves /api/chat against the configured baseURL") {
        let base = URL(string: "http://localhost:11434")!
        let client = OllamaClient(baseURL: base, model: "gemma4_2b:latest")
        try expectEqual(client.chatURL.absoluteString, "http://localhost:11434/api/chat")
    }

    s.test("OllamaClient preserves a trailing-slash baseURL") {
        let base = URL(string: "http://localhost:11434/")!
        let client = OllamaClient(baseURL: base, model: "m")
        try expectEqual(client.chatURL.absoluteString, "http://localhost:11434/api/chat")
    }

    return s
}
