import Foundation

/// Capabilities reported by `/api/v1/model`, `/api/extra/version`,
/// `/api/extra/true_max_context_length`. Cached on the profile so the
/// UI can render a sensible "last-known model" without a fresh probe.
public struct ServerCapabilities: Codable, Equatable {
    public var modelName: String?
    public var trueMaxContext: Int?
    public var version: String?

    public init(modelName: String? = nil, trueMaxContext: Int? = nil, version: String? = nil) {
        self.modelName = modelName
        self.trueMaxContext = trueMaxContext
        self.version = version
    }
}

/// A single configured kobold endpoint. Loom Phase 1 has no per-role
/// routing (RPClient's general / summarizer / extractor / embeddings
/// split is irrelevant here — Continue + Expand both use the project's
/// chosen profile, falling back to AppSettings.defaultServerId, falling
/// back to localhost). Phase 2+ may add roles when side-call work
/// (rolling summary, fact extraction) lands.
public struct ServerProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var capabilities: ServerCapabilities?
    public var lastProbed: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        capabilities: ServerCapabilities? = nil,
        lastProbed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.capabilities = capabilities
        self.lastProbed = lastProbed
    }
}
