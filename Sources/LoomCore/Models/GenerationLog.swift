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
    /// Phase 7.b followup — template-generation metadata. Non-nil only
    /// for entries written by `TemplateGenerationCoordinator`. The
    /// `mode` field stays as `.continueProse` (least-wrong existing
    /// case for "wrote prose into the scene") to avoid churning every
    /// `switch mode` site; this side field carries the template-
    /// specific info for replay / audit. Optional + `decodeIfPresent`
    /// so pre-Phase-7 log entries on disk still load cleanly.
    public var templateGenerationInfo: TemplateGenerationInfo?

    public init(
        id: UUID = UUID(),
        sceneId: UUID,
        timestamp: Date = Date(),
        mode: GenerationMode,
        model: String? = nil,
        serverProfileId: UUID? = nil,
        promptAssembly: PromptAssembly,
        response: GenerationResponse,
        templateGenerationInfo: TemplateGenerationInfo? = nil
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
        self.templateGenerationInfo = templateGenerationInfo
    }

    private enum CodingKeys: String, CodingKey {
        case id, sceneId, timestamp, mode, model, serverProfileId
        case promptAssembly, response, templateGenerationInfo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.sceneId = try c.decode(UUID.self, forKey: .sceneId)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.mode = try c.decode(GenerationMode.self, forKey: .mode)
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.serverProfileId = try c.decodeIfPresent(UUID.self, forKey: .serverProfileId)
        self.promptAssembly = try c.decode(PromptAssembly.self, forKey: .promptAssembly)
        self.response = try c.decode(GenerationResponse.self, forKey: .response)
        self.templateGenerationInfo = try c.decodeIfPresent(
            TemplateGenerationInfo.self, forKey: .templateGenerationInfo
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sceneId, forKey: .sceneId)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(serverProfileId, forKey: .serverProfileId)
        try c.encode(promptAssembly, forKey: .promptAssembly)
        try c.encode(response, forKey: .response)
        try c.encodeIfPresent(templateGenerationInfo, forKey: .templateGenerationInfo)
    }
}

/// Phase 7.b followup — side-table for the template-specific bits of
/// a generation event. Includes template id + name + cast mapping +
/// beat count + the per-beat modality sequence + voice descriptor.
/// Enough metadata for the History tab to render a template gen
/// distinctively from a Continue, and for the user to know which
/// template a given scene came from + with what cast / setting prompt.
public struct TemplateGenerationInfo: Codable, Equatable {
    public let templateId: UUID
    public let templateName: String
    public let castMapping: String
    public let beatCount: Int
    public let beatModalitySequence: [String]
    public let voiceDescriptor: VoiceDescriptor?

    public init(
        templateId: UUID,
        templateName: String,
        castMapping: String,
        beatCount: Int,
        beatModalitySequence: [String],
        voiceDescriptor: VoiceDescriptor?
    ) {
        self.templateId = templateId
        self.templateName = templateName
        self.castMapping = castMapping
        self.beatCount = beatCount
        self.beatModalitySequence = beatModalitySequence
        self.voiceDescriptor = voiceDescriptor
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
