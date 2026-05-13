import Foundation

/// Phase 5 production `EmbeddingClient` conformer that runs StyleDistance
/// in a long-lived Python subprocess. Pivoted from in-Swift MLX after the
/// MLX-Swift package was found to require full Xcode (for the `metal`
/// compiler) — see [`LOOM_MLX_PORT_SPIKE.md`](../../LOOM_MLX_PORT_SPIKE.md) §12.
///
/// Architecture: a single Python interpreter loads the model once and
/// serves embed requests via stdin/stdout JSON-line protocol until
/// stdin closes. The subprocess is the parent's child — it dies
/// automatically with the parent (no daemon, no port management, no
/// HTTP server, no separate code-signing pipeline for a launcher).
///
/// Protocol pinned here:
///
/// - stdin: one JSON object per line, shape `{"text": "..."}`
/// - stdout: one JSON object per line:
///   - `{"ready": true}` once, after model load — signals client to unblock
///   - `{"dim": 768, "vec": [...]}` per successful embed
///   - `{"error": "..."}` per failure (model load, embed exception, etc.)
/// - stderr: free-form status lines, not consumed by the client
///
/// This module owns the request body builder + response parser. The
/// subprocess management (spawn, pipe IO, lifecycle) lives in the
/// concrete client class below — integration territory, validated by
/// `Tools/RagSpike --venv-smoke`.

public enum PythonEmbedRequest {
    public static func body(text: String) -> Data {
        let payload: [String: Any] = ["text": text]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

public enum PythonEmbedResponse {
    public static func decode(_ data: Data) -> EmbeddingVector? {
        struct Wire: Decodable {
            let dim: Int?
            let vec: [Float]?
            let error: String?
            let ready: Bool?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        guard wire.error == nil, wire.ready != true else { return nil }
        guard let vec = wire.vec, !vec.isEmpty else { return nil }
        return EmbeddingVector(values: vec)
    }

    public static func isReady(_ data: Data) -> Bool {
        struct Wire: Decodable { let ready: Bool? }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return false }
        return wire.ready == true
    }
}

/// Long-lived subprocess client. Spawns Python on first `embed(_:)`
/// call (lazy load), then reuses the subprocess for every subsequent
/// embed. Subprocess shuts down when this client is deinit'd (the
/// stdin pipe closes, the Python script's stdin loop exits).
///
/// Synchronous external API per the `EmbeddingClient` protocol. Each
/// `embed(_:)` call blocks the caller's thread until the subprocess
/// writes a response. Production callers (ingest, retrieval) run
/// off the main thread.
public final class PythonStyleDistanceClient: EmbeddingClient {
    public let modelId: String
    public let dim: Int

    private let pythonExecutable: URL
    private let scriptPath: URL
    private let workingDirectory: URL
    private let readyTimeoutSeconds: TimeInterval

    /// Lazily-initialised subprocess + pipes. Lock protects the
    /// first-spawn race and per-call read/write atomicity.
    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutReader: LineReader?

    public init(
        pythonExecutable: URL,
        scriptPath: URL,
        workingDirectory: URL,
        modelId: String = "StyleDistance/styledistance (Python subprocess)",
        dim: Int = 768,
        readyTimeoutSeconds: TimeInterval = 120
    ) {
        self.pythonExecutable = pythonExecutable
        self.scriptPath = scriptPath
        self.workingDirectory = workingDirectory
        self.modelId = modelId
        self.dim = dim
        self.readyTimeoutSeconds = readyTimeoutSeconds
    }

    deinit {
        // Closing stdin signals the Python script's stdin loop to
        // exit cleanly; the subprocess exits soon after.
        stdinHandle?.closeFile()
        process?.waitUntilExit()
    }

    public func embed(_ text: String) -> EmbeddingVector? {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureStartedLocked()
        } catch {
            return nil
        }
        guard let stdin = stdinHandle, let reader = stdoutReader else { return nil }

        let body = PythonEmbedRequest.body(text: text)
        var line = Data(body)
        line.append(0x0a) // '\n'
        do {
            try stdin.write(contentsOf: line)
        } catch {
            return nil
        }

        // Read response lines until we get a vector or error;
        // skip ready-signals (shouldn't appear post-init).
        while let respLine = reader.readLine() {
            if PythonEmbedResponse.isReady(respLine) { continue }
            return PythonEmbedResponse.decode(respLine)
        }
        return nil
    }

    private func ensureStartedLocked() throws {
        if process != nil { return }

        let task = Process()
        task.executableURL = pythonExecutable
        task.arguments = [scriptPath.path]
        task.currentDirectoryURL = workingDirectory

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        // Drain stderr so the subprocess doesn't block on a full
        // pipe; we don't structurally consume stderr.
        let stderrPipe = Pipe()
        task.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { _ = $0.availableData }

        try task.run()
        self.process = task
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutReader = LineReader(handle: stdoutPipe.fileHandleForReading)

        // Wait for the `{"ready": true}` signal so the first embed
        // call doesn't race the model load.
        let deadline = Date().addingTimeInterval(readyTimeoutSeconds)
        while Date() < deadline {
            guard let line = stdoutReader?.readLine() else {
                throw PythonClientError.subprocessExitedBeforeReady
            }
            if PythonEmbedResponse.isReady(line) { return }
            // Otherwise it might be a startup error line — surface it.
            if let wire = try? JSONDecoder().decode([String: String].self, from: line),
               let err = wire["error"] {
                throw PythonClientError.startupError(err)
            }
        }
        throw PythonClientError.readyTimeout
    }
}

public enum PythonClientError: Error, Equatable {
    case subprocessExitedBeforeReady
    case readyTimeout
    case startupError(String)
}

/// Helper: read newline-delimited records from a FileHandle. Buffers
/// internally so partial reads are handled correctly. Returns nil
/// on EOF.
private final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() -> Data? {
        while !buffer.contains(0x0a) {
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
        guard let newlineIdx = buffer.firstIndex(of: 0x0a) else { return nil }
        let line = buffer[..<newlineIdx]
        buffer.removeSubrange(...newlineIdx)
        return Data(line)
    }
}
