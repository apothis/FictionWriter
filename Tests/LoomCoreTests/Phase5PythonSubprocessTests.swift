import Foundation
@testable import LoomCore

/// Pure-data tests for the Python subprocess JSON line protocol.
/// The subprocess management (spawn / pipe / lifecycle) is integration
/// territory — validated by `Tools/RagSpike --venv-smoke` against the
/// real subprocess. What we pin here is the wire format.
func phase5PythonSubprocessTests() -> TestSuite {
    let s = TestSuite("Phase5PythonSubprocess")

    // MARK: - Request body

    s.test("request encodes a single-text JSON line") {
        let data = PythonEmbedRequest.body(text: "She walked.")
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expectEqual(decoded["text"] as? String, "She walked.")
    }

    s.test("request body has no trailing newline (caller appends one)") {
        // Keeping newlines out of the body lets the caller decide
        // framing — convention is line-delimited JSON, but the
        // protocol detail belongs at the IO boundary, not in the
        // body builder.
        let data = PythonEmbedRequest.body(text: "x")
        let str = String(data: data, encoding: .utf8) ?? ""
        try expectFalse(str.contains("\n"))
    }

    s.test("request handles strings with embedded newlines safely (JSON escaping)") {
        let data = PythonEmbedRequest.body(text: "line one\nline two")
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expectEqual(decoded["text"] as? String, "line one\nline two")
        // Body itself must not have raw newlines in the value position.
        let str = String(data: data, encoding: .utf8) ?? ""
        try expectFalse(str.contains("\n"))
    }

    // MARK: - Response parser

    s.test("response parser decodes a 768-dim embedding") {
        let json = """
        {"dim": 3, "vec": [0.1, 0.2, -0.3]}
        """.data(using: .utf8)!
        let vec = try expectNotNil(PythonEmbedResponse.decode(json))
        try expectEqual(vec.dim, 3)
        try expectEqual(vec.values, [0.1, 0.2, -0.3])
    }

    s.test("response parser returns nil for ready signal (not an embedding)") {
        // The ready signal is `{"ready": true}` — emitted once at
        // subprocess startup to indicate model loaded. The client
        // consumes this separately; the response parser shouldn't
        // confuse it for a vector.
        let json = """
        {"ready": true}
        """.data(using: .utf8)!
        try expectNil(PythonEmbedResponse.decode(json))
    }

    s.test("response parser returns nil for error responses") {
        let json = """
        {"error": "model load failed"}
        """.data(using: .utf8)!
        try expectNil(PythonEmbedResponse.decode(json))
    }

    s.test("response parser returns nil for malformed JSON") {
        try expectNil(PythonEmbedResponse.decode(Data("not json".utf8)))
    }

    s.test("response parser returns nil for empty vec array") {
        let json = """
        {"dim": 0, "vec": []}
        """.data(using: .utf8)!
        try expectNil(PythonEmbedResponse.decode(json))
    }

    s.test("response parser recognises the ready signal via isReady(_:)") {
        let ready = """
        {"ready": true}
        """.data(using: .utf8)!
        try expectTrue(PythonEmbedResponse.isReady(ready))

        let vec = """
        {"dim": 3, "vec": [0.1, 0.2, 0.3]}
        """.data(using: .utf8)!
        try expectFalse(PythonEmbedResponse.isReady(vec))

        let err = """
        {"error": "x"}
        """.data(using: .utf8)!
        try expectFalse(PythonEmbedResponse.isReady(err))
    }

    return s
}
