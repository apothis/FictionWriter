import Foundation

/// One generation event, persisted to disk as a single JSON file under
/// `<project>/generation-log/<timestamp>-<uuid>.json`. Captures the
/// full assembled prompt + response so the History tab can show "what
/// was sent / what came back" — the headline transparency feature per
/// LOOM_DESIGN_LANGUAGE.md §14.5.2.
public struct GenerationLogEntry: Codable, Equatable {
    public let id: UUID
    public let sceneId: UUID
    public let timestamp: Date
    public let mode: GenerationMode
    public var model: String?
    public var serverProfileId: UUID?
    public var promptAssembly: PromptAssembly
    public var response: GenerationResponse

    public init(
        id: UUID = UUID(),
        sceneId: UUID,
        timestamp: Date = Date(),
        mode: GenerationMode,
        model: String? = nil,
        serverProfileId: UUID? = nil,
        promptAssembly: PromptAssembly,
        response: GenerationResponse
    ) {
        self.id = id
        self.sceneId = sceneId
        // Round to ms so round-trip identity holds (matches the
        // Project.createdAt convention from JSONCoders).
        self.timestamp = LoomISO8601.roundedToMillisecond(timestamp)
        self.mode = mode
        self.model = model
        self.serverProfileId = serverProfileId
        self.promptAssembly = promptAssembly
        self.response = response
    }
}

/// The prompt side of the generation event. Mirrors the AssembledPrompt
/// shape (PromptBuilder's output) but carries chiclets + cache-bookkeeping
/// in a Codable form for persistence.
public struct PromptAssembly: Codable, Equatable {
    public var contextChiclets: [ContextChiclet]
    public var fullPrompt: String
    public var promptTokens: Int
    public var aboveCacheTokens: Int
    public var belowCacheTokens: Int
    public var evictedLayers: [String]
    public var template: InstructTemplate

    public init(
        contextChiclets: [ContextChiclet],
        fullPrompt: String,
        promptTokens: Int,
        aboveCacheTokens: Int,
        belowCacheTokens: Int,
        evictedLayers: [String],
        template: InstructTemplate
    ) {
        self.contextChiclets = contextChiclets
        self.fullPrompt = fullPrompt
        self.promptTokens = promptTokens
        self.aboveCacheTokens = aboveCacheTokens
        self.belowCacheTokens = belowCacheTokens
        self.evictedLayers = evictedLayers
        self.template = template
    }
}

/// The response side of the generation event.
public struct GenerationResponse: Codable, Equatable {
    public var rawText: String
    public var completionTokens: Int
    public var stopReason: String?
    public var refusalDetected: Bool
    public var elapsedMs: Int

    public init(
        rawText: String,
        completionTokens: Int,
        stopReason: String? = nil,
        refusalDetected: Bool = false,
        elapsedMs: Int
    ) {
        self.rawText = rawText
        self.completionTokens = completionTokens
        self.stopReason = stopReason
        self.refusalDetected = refusalDetected
        self.elapsedMs = elapsedMs
    }
}
