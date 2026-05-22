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

/// What backend shape a `ServerProfile` speaks. Phase 4 #7's role-
/// routed extractor (LOOM_LEDGER_SPIKE.md §11–§12) introduced the
/// second backend: KoboldCpp for the writer, Ollama for the ledger
/// extractor. Forward-load contract: pre-Phase-4 settings.json
/// bundles have no `kind` field on profiles and must decode as
/// `.kobold` (see ServerProfile.init(from:)).
public enum ServerKind: String, Codable {
    case kobold
    case ollama
}

/// A single configured backend endpoint. Phase 1 was kobold-only;
/// Phase 4 #7 adds `.ollama` so a single `AppSettings.servers` list
/// can carry both the writer (KoboldCpp) and the extractor
/// (Ollama running gemma4_2b in the production design). Role
/// assignment lives on `AppSettings` (`defaultServerId` for the
/// writer, `extractorServerId` for the extractor); `kind` here is
/// the wire-protocol discriminator the network layer reads to pick
/// `/api/v1/generate` (kobold) vs `/api/chat` (ollama).
public struct ServerProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var kind: ServerKind
    /// Explicit model selection for this endpoint. For Ollama this is
    /// the model the extractor calls (`gemma4_2b:latest` etc.) — a multi-
    /// model Ollama install otherwise leaves the choice to the probe's
    /// "first in /api/tags", which is order-dependent and could even
    /// resolve to an embedding model. For Kobold this informs instruct-
    /// template detection when the probe didn't capture a model name.
    /// `nil` = fall back to the probed `capabilities.modelName`.
    public var model: String?
    public var capabilities: ServerCapabilities?
    public var lastProbed: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        kind: ServerKind = .kobold,
        model: String? = nil,
        capabilities: ServerCapabilities? = nil,
        lastProbed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.model = model
        self.capabilities = capabilities
        self.lastProbed = lastProbed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.baseURL = try c.decode(URL.self, forKey: .baseURL)
        self.kind = try c.decodeIfPresent(ServerKind.self, forKey: .kind) ?? .kobold
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.capabilities = try c.decodeIfPresent(ServerCapabilities.self, forKey: .capabilities)
        self.lastProbed = try c.decodeIfPresent(Date.self, forKey: .lastProbed)
    }
}
