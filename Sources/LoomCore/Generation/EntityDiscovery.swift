import Foundation

/// Phase 9 entity-discovery — pure-data types.
///
/// LOOM_ENTITY_DISCOVERY_SPIKE §3.2: shapes for the six-stage pipeline
/// that extends Pass-B (LedgerExtraction) to *discover* new characters
/// and places in scene prose, attach facts, and surface them in the
/// Bible Workspace webview as accept/reject/edit suggestions.
///
/// Sibling namespace to `LedgerExtraction`. Shapes are designed so
/// `ExtractedFact.characterId` can reference either a real
/// `Character.id` (existing bible row) or a `ProposedEntity.id`
/// (not yet promoted) — same string-typed field, no schema break.
public enum EntityDiscovery {

    // MARK: - Types

    public enum Kind: String, Codable, Equatable, CaseIterable {
        case character
        case place
        /// v2 extension — `BibleObject` (significant artefacts).
        /// Same gate logic as characters (proper-noun or "The X").
        /// Place-recurrence filter does NOT fire on objects: a
        /// single-mention named artefact (Excalibur, The
        /// Necronomicon) is bible-worthy.
        case object
    }

    /// A discovered entity that has cleared the promotion gate (§3.1
    /// Stage B) and dedup (§3.1 Stage C) but has not yet been accepted
    /// by the user. Promoted to a real `Character` / `Setting` on
    /// `acceptEntityProposal` bridge intent.
    public struct ProposedEntity: Codable, Equatable {
        public let id: UUID
        public let kind: Kind
        public let canonicalName: String
        public let aliases: [String]
        public let oneLine: String
        public let evidenceQuote: String
        public let sourceSceneId: UUID
        /// 0…1 gate output. Clamped at construction so a buggy LLM
        /// emit can never crash the pipeline downstream.
        public let confidence: Double

        public init(
            id: UUID,
            kind: Kind,
            canonicalName: String,
            aliases: [String],
            oneLine: String,
            evidenceQuote: String,
            sourceSceneId: UUID,
            confidence: Double
        ) {
            self.id = id
            self.kind = kind
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.oneLine = oneLine
            self.evidenceQuote = evidenceQuote
            self.sourceSceneId = sourceSceneId
            self.confidence = max(0.0, min(1.0, confidence))
        }
    }

    /// Bundle of facts attached to one proposed entity. On accept,
    /// facts flow into the bible alongside the promoted entity in a
    /// single atomic operation (Phase 4 fact-merge semantics apply
    /// per existing `LedgerSuggestionAcceptor`).
    public struct ProposedEntityFacts: Codable, Equatable {
        public let proposedEntityId: UUID
        public let facts: [LedgerExtraction.ExtractedFact]

        public init(proposedEntityId: UUID, facts: [LedgerExtraction.ExtractedFact]) {
            self.proposedEntityId = proposedEntityId
            self.facts = facts
        }
    }

    // MARK: - Stage B: anatomy-descriptor block-list (§4.6)

    /// Anatomy descriptors that, when they ARE the whole canonical
    /// name (modulo a generic noun + leading determiner), should
    /// block promotion. NSFW prose identifies otherwise-unnamed
    /// characters by hair/skin/build features; promoting these as
    /// distinct characters duplicates ones the user already has
    /// permanent names for. Kept narrow on purpose: only add a root
    /// here once the live spike surfaces a recurring false-positive.
    static let anatomyDescriptorRoots: Set<String> = [
        "redhead", "redheads", "redheaded",
        "brunette", "brunettes",
        "blonde", "blond", "blondes", "blonds",
    ]

    /// Generic nouns that anatomy descriptors typically modify
    /// ("the brunette woman", "the blonde girl"). When a phrase is
    /// wholly `{anatomy} + {generic}` modulo determiner, it's still
    /// anatomy-only and gets rejected.
    static let genericPersonNouns: Set<String> = [
        "woman", "women", "girl", "girls",
        "man", "men", "boy", "boys",
        "lady", "ladies", "person", "people",
    ]

    static let leadingDeterminers: Set<String> = ["the", "a", "an"]

    /// Returns true iff the given canonical-name candidate is
    /// *wholly* an anatomy-descriptor phrase (i.e. anatomy root,
    /// optionally with leading determiner + trailing generic noun).
    /// Any other content word — proper noun, occupation, location
    /// modifier — flips the answer to false so the entity is kept.
    public static func isAnatomyOnlyDescriptor(_ candidate: String) -> Bool {
        var words = candidate
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
        // Strip a single leading determiner if present.
        if let first = words.first, leadingDeterminers.contains(first) {
            words.removeFirst()
        }
        guard !words.isEmpty else { return false }
        // Every remaining word must be anatomy or a generic person
        // noun. A single unknown word (proper noun, role, "captain")
        // disqualifies the reject.
        var sawAnatomy = false
        for w in words {
            if anatomyDescriptorRoots.contains(w) {
                sawAnatomy = true
            } else if genericPersonNouns.contains(w) {
                // generic alone isn't anatomy-only, but generic
                // alongside anatomy is — track and check at end.
                continue
            } else {
                return false
            }
        }
        return sawAnatomy
    }

    // MARK: - Pre-gate: known-entity filter (§6.4 first-run fix)

    /// Returns true iff `surface` (case-insensitive, whitespace-
    /// trimmed) is an exact match for any name in `knownNames`. Used
    /// to drop Stage A2 candidates that the model re-emitted despite
    /// the prompt instructing it not to (gemma4_2b ignores prompt
    /// blacklists; structural enforcement does not). Partial overlap
    /// ("Vance" vs "Karim Vance") is NOT caught here — that's the
    /// dedup stage's cosine-similarity job.
    public static func isKnownSurface(_ surface: String, knownNames: [String]) -> Bool {
        let needle = surface.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return false }
        for name in knownNames {
            if name.lowercased().trimmingCharacters(in: .whitespaces) == needle {
                return true
            }
        }
        return false
    }

    /// Filter a list of Stage A2 candidates, keeping only those
    /// whose surface is NOT in `knownNames`. Order-preserving.
    public static func filterKnown(_ candidates: [Candidate], knownNames: [String]) -> [Candidate] {
        candidates.filter { !isKnownSurface($0.surface, knownNames: knownNames) }
    }

    /// Expand a known-names list with proper-noun tokens extracted
    /// from multi-word entries. "Karim Vance" → adds "Karim" + "Vance"
    /// so a Stage A2 candidate emitted as just "Vance" gets filtered
    /// as already-known. Token criteria: starts uppercase + length
    /// ≥ 3 (drops titles "Mr"/"Dr" and determiners "the"/"an" that
    /// would over-match). Output deduplicated, order not preserved.
    public static func expandKnownNamesWithTokens(_ names: [String]) -> [String] {
        var out = Set<String>(names)
        for name in names {
            let tokens = name.split(separator: " ").map(String.init)
            guard tokens.count >= 2 else { continue }
            for t in tokens {
                guard t.count >= 3 else { continue }
                guard let first = t.unicodeScalars.first,
                      CharacterSet.uppercaseLetters.contains(first) else { continue }
                out.insert(t)
            }
        }
        return Array(out)
    }

    /// Place-specific recurrence gate (§6.4 first-run fix). A
    /// `.place` candidate passes iff its surface starts with "The "
    /// (definite article as part of the proper name) OR it appears
    /// ≥ 2 times in the scene prose. Characters bypass this filter
    /// entirely — they have separate gate logic. Single-pass-mention
    /// real-world cities (Brussels, Edinburgh in eds-07) are exactly
    /// the failure mode this catches.
    public static func passesPlaceRecurrence(surface: String, kind: Kind, scenePose: String) -> Bool {
        guard kind == .place else { return true }
        let trimmed = surface.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("the ") {
            return true
        }
        return wordOccurrenceCount(needle: trimmed, in: scenePose) >= 2
    }

    /// Whole-word case-insensitive count of `needle` in `haystack`.
    /// "Brusselsprouts" doesn't count as a "Brussels" mention.
    static func wordOccurrenceCount(needle: String, in haystack: String) -> Int {
        let lowerHaystack = haystack.lowercased()
        let lowerNeedle = needle.lowercased()
        guard !lowerNeedle.isEmpty else { return 0 }
        var count = 0
        var searchRange = lowerHaystack.startIndex..<lowerHaystack.endIndex
        while let r = lowerHaystack.range(of: lowerNeedle, range: searchRange) {
            let beforeOK: Bool
            if r.lowerBound == lowerHaystack.startIndex {
                beforeOK = true
            } else {
                let c = lowerHaystack[lowerHaystack.index(before: r.lowerBound)]
                beforeOK = !c.isLetter && !c.isNumber
            }
            let afterOK: Bool
            if r.upperBound == lowerHaystack.endIndex {
                afterOK = true
            } else {
                let c = lowerHaystack[r.upperBound]
                afterOK = !c.isLetter && !c.isNumber
            }
            if beforeOK && afterOK {
                count += 1
            }
            searchRange = r.upperBound..<lowerHaystack.endIndex
        }
        return count
    }

    // MARK: - Stage A2: candidate generation (grammar / schema / prompt / parser)

    /// Candidate generation output — a single entity mention as it
    /// first appears in the scene prose. Light shape on purpose;
    /// Stage D normalises into the richer `ProposedEntity` tuple.
    public struct Candidate: Equatable {
        public let surface: String
        public let kind: Kind
        public let firstSeenQuote: String

        public init(surface: String, kind: Kind, firstSeenQuote: String) {
            self.surface = surface
            self.kind = kind
            self.firstSeenQuote = firstSeenQuote
        }
    }

    public enum ParseError: Error {
        case noJSONArrayFound
        case noJSONObjectFound
        case malformedJSON
        /// Stage A2 line output had no parseable candidate lines even
        /// after a retry — the model never produced the list format.
        case noParseableCandidates
    }

    /// Collapse Stage A2 candidates sharing a surface form (case-
    /// insensitive, trimmed) AND kind down to their first occurrence.
    /// Live-smoke: the reworded A2 prompt made gemma4_2b emit one
    /// candidate per *mention* — a 1263-word scene yielded 30
    /// candidates for 3 distinct entities. Each duplicate would fire
    /// its own Stage D normalisation call, serialised through Ollama,
    /// turning a ~30s discovery into minutes. Runs before Stage D so
    /// the fan-out matches the entity count, not the mention count.
    public static func dedupCandidatesBySurface(_ candidates: [Candidate]) -> [Candidate] {
        struct Key: Hashable {
            let surface: String
            let kind: Kind
        }
        var seen: Set<Key> = []
        var out: [Candidate] = []
        for c in candidates {
            let key = Key(
                surface: c.surface.lowercased().trimmingCharacters(in: .whitespaces),
                kind: c.kind
            )
            if seen.insert(key).inserted {
                out.append(c)
            }
        }
        return out
    }

    /// GBNF grammar for Stage A2 (kobold-side). Empirical guards
    /// from LedgerExtraction §164 baked in: single-optional-space
    /// `ws`, rules on one line, simple string-escape handling.
    public static func candidateGenerationGBNF() -> String {
        return "root ::= \"[\" ws (candidate (ws \",\" ws candidate)*)? ws \"]\"\n"
            + "candidate ::= \"{\" ws \"\\\"surface\\\":\" ws string ws \",\" ws \"\\\"kind\\\":\" ws kind ws \",\" ws \"\\\"first_seen_quote\\\":\" ws string ws \"}\"\n"
            + "kind ::= \"\\\"character\\\"\" | \"\\\"place\\\"\" | \"\\\"object\\\"\"\n"
            + "string ::= \"\\\"\" ([^\"\\\\] | \"\\\\\" .)* \"\\\"\"\n"
            + "ws ::= \" \"?"
    }

    /// JSON Schema for Stage A2 (Ollama-side `format` field).
    public static func candidateGenerationJSONSchema() -> [String: Any] {
        return [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "surface": ["type": "string"],
                    "kind": ["type": "string", "enum": ["character", "place", "object"]],
                    "first_seen_quote": ["type": "string"],
                ],
                "required": ["surface", "kind", "first_seen_quote"],
            ],
        ]
    }

    // "new" deliberately absent: with an empty known-list every
    // entity is new to the bible, but the word made gemma4_2b scope
    // to narrative recency and emit only the most-recently-discussed
    // character. Dedup against the bible is the known-list line's
    // job (see buildCandidateGenerationPrompt), not the instruction.
    public static let candidateGenerationPromptInstruction =
        "Identify every character, named place, and named significant object (e.g. named weapons, named artefacts, named vehicles) that appears in the scene below. List every character — those who act or speak in the scene as well as those who are only spoken about by others. Only emit entities that have a clear proper noun — do not emit entries for generic references like \"the man\", \"the bedroom\", \"the cafe\", \"the cup\". For each entity, emit one entry with the surface form as it appears, the kind (character, place, or object), and a verbatim quote where the entity first appears."

    public static func buildCandidateGenerationPrompt(
        scenePose: String,
        knownEntityNames: [String]
    ) -> String {
        let knownJSON: String = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(knownEntityNames)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }()
        return """
        \(Self.candidateGenerationPromptInstruction)

        Do NOT emit entries for entities already in this known list:
        \(knownJSON)

        Respond with ONLY a JSON array. Each element is an object with exactly these three keys:
          "surface" — the entity's name exactly as written in the scene
          "kind" — one of "character", "place", "object"
          "first_seen_quote" — a verbatim sentence from the scene where the entity first appears
        Example: [{"surface": "Jane Doe", "kind": "character", "first_seen_quote": "Jane Doe opened the door."}]

        Scene:
        \(scenePose)

        Emit the JSON array.
        """
    }

    /// Stage A2 prompt asking for a **line list** rather than a JSON
    /// array. Small models reliably emit a delimited line list but
    /// flake when juggling nested-JSON syntax — there are no braces,
    /// quotes or commas to balance, and a truncated emit still yields
    /// every complete line. Parsed by `parseCandidateLines`.
    public static func buildCandidateListPrompt(
        scenePose: String,
        knownEntityNames: [String]
    ) -> String {
        let knownJSON: String = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(knownEntityNames)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }()
        return """
        You are an indexing tool that catalogues the named entities in a manuscript. You do not summarise, judge, or comment on the text — you only list the entities it contains.

        \(Self.candidateGenerationPromptInstruction)

        Do NOT list entities already in this known list:
        \(knownJSON)

        Output one entity per line, and nothing else — no preamble, no JSON, no commentary. Each line must have exactly three fields separated by " | ":
        kind | surface | quote
        where kind is character, place, or object; surface is the entity name exactly as written in the scene; and quote is a short verbatim phrase from the scene where the entity first appears.

        Scene:
        \(scenePose)

        Begin the list now.
        """
    }

    /// Parse the line-based Stage A2 output: one entity per line,
    /// `kind | surface | quote`. Tolerant — skips blank lines, header
    /// noise, lines without the three pipe-delimited fields, and
    /// unrecognised kinds. Never throws: 0 results means the model
    /// produced nothing parseable (the caller decides retry vs empty).
    public static func parseCandidateLines(_ raw: String) -> [Candidate] {
        var out: [Candidate] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            // maxSplits 2 so a pipe inside the quote stays intact.
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let kindStr = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let surface = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let quote = String(parts[2]).trimmingCharacters(in: .whitespaces)
            // Substring match — the model sometimes elaborates the
            // kind word ("significant object", "named place").
            let kind: Kind
            if kindStr.contains("character") { kind = .character }
            else if kindStr.contains("place") { kind = .place }
            else if kindStr.contains("object") { kind = .object }
            else { continue }
            guard !surface.isEmpty else { continue }
            out.append(Candidate(surface: surface, kind: kind, firstSeenQuote: quote))
        }
        return out
    }

    /// Parser tolerant of preamble / postamble and mid-array
    /// truncation — mirrors `LedgerExtraction.parseExtractedFacts`.
    public static func parseCandidates(_ raw: String) throws -> [Candidate] {
        guard let first = raw.firstIndex(of: "[") else {
            throw ParseError.noJSONArrayFound
        }
        // Strict full-array decode first.
        if let last = raw.lastIndex(of: "]"), last > first {
            let slice = String(raw[first...last])
            if let data = slice.data(using: .utf8),
               let items = try? JSONDecoder().decode([RawCandidate].self, from: data)
            {
                return items.compactMap { candidateFromRaw($0) }
            }
        }
        // Per-object recovery for truncated arrays.
        return recoverCandidatesPerObject(raw[first...])
    }

    private struct RawCandidate: Decodable {
        let surface: String?
        let kind: String?
        let first_seen_quote: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKey.self)
            // Unconstrained generation (no `format` schema) means the
            // model picks its own key names — accept the common
            // synonyms so candidates aren't silently dropped.
            func str(_ keys: [String]) -> String? {
                for k in keys {
                    if let key = DynamicCodingKey(stringValue: k),
                       let v = try? c.decodeIfPresent(String.self, forKey: key) {
                        return v
                    }
                }
                return nil
            }
            surface = str(["surface", "surface_form", "name"])
            kind = str(["kind", "type"])
            first_seen_quote = str(["first_seen_quote", "quote", "evidence_quote", "evidence"])
        }
    }

    private static func candidateFromRaw(_ r: RawCandidate) -> Candidate? {
        guard let s = r.surface, !s.isEmpty,
              let k = r.kind, let kind = Kind(rawValue: k),
              let q = r.first_seen_quote
        else { return nil }
        return Candidate(surface: s, kind: kind, firstSeenQuote: q)
    }

    private static func recoverCandidatesPerObject(_ slice: Substring) -> [Candidate] {
        var out: [Candidate] = []
        var depth = 0
        var start: String.Index?
        for i in slice.indices {
            let c = slice[i]
            if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    let objStr = String(slice[s...i])
                    if let data = objStr.data(using: .utf8),
                       let r = try? JSONDecoder().decode(RawCandidate.self, from: data),
                       let cand = candidateFromRaw(r)
                    {
                        out.append(cand)
                    }
                    start = nil
                }
            }
        }
        return out
    }

    // MARK: - Stage D: normalisation (grammar / schema / prompt / parser)

    /// Normalised entity — Stage D output. Becomes the body of a
    /// `ProposedEntity` once the orchestrator adds id + sceneId +
    /// confidence (which come from the pipeline, not the LLM).
    public struct NormalisedEntity: Equatable {
        public let kind: Kind
        public let canonicalName: String
        public let aliases: [String]
        public let oneLine: String
        public let evidenceQuote: String

        public init(kind: Kind, canonicalName: String, aliases: [String], oneLine: String, evidenceQuote: String) {
            self.kind = kind
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.oneLine = oneLine
            self.evidenceQuote = evidenceQuote
        }
    }

    public static func normalisationGBNF() -> String {
        return "root ::= \"{\" ws \"\\\"kind\\\":\" ws kind ws \",\" ws \"\\\"canonical_name\\\":\" ws string ws \",\" ws \"\\\"aliases\\\":\" ws aliases ws \",\" ws \"\\\"one_line\\\":\" ws string ws \",\" ws \"\\\"evidence_quote\\\":\" ws string ws \"}\"\n"
            + "kind ::= \"\\\"character\\\"\" | \"\\\"place\\\"\" | \"\\\"object\\\"\"\n"
            + "aliases ::= \"[\" ws (string (ws \",\" ws string)*)? ws \"]\"\n"
            + "string ::= \"\\\"\" ([^\"\\\\] | \"\\\\\" .)* \"\\\"\"\n"
            + "ws ::= \" \"?"
    }

    public static func normalisationJSONSchema() -> [String: Any] {
        return [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": ["character", "place", "object"]],
                "canonical_name": ["type": "string"],
                "aliases": ["type": "array", "items": ["type": "string"]],
                "one_line": ["type": "string"],
                "evidence_quote": ["type": "string"],
            ],
            "required": ["kind", "canonical_name", "aliases", "one_line", "evidence_quote"],
        ]
    }

    public static let normalisationPromptInstruction =
        "Normalise the entity candidate below into a structured bible entry. For canonical_name, use the most complete/formal form of the name that appears in the scene (e.g. \"Marius Thorn\" not \"Marius\"). For aliases, list every other surface form of this entity that appears in the scene. For one_line, write a single sentence describing this entity based on the scene. For evidence_quote, cite a verbatim span from the scene that anchors the entity's identity."

    public static func buildNormalisationPrompt(
        candidateSurface: String,
        candidateKind: Kind,
        firstSeenQuote: String,
        scenePose: String
    ) -> String {
        return """
        \(Self.normalisationPromptInstruction)

        Candidate surface: "\(candidateSurface)"
        Kind: \(candidateKind.rawValue)
        First seen quote: "\(firstSeenQuote)"

        Scene:
        \(scenePose)

        Emit the JSON object.
        """
    }

    /// Post-Stage-D dedup: merge entries sharing a canonical_name
    /// (case-insensitive, trimmed) AND kind. Aliases unioned;
    /// `one_line` + `evidence_quote` keep the first occurrence's
    /// values so the user-visible context survives. Order-stable
    /// for kept entries. Complements the embedding-based pre-LLM
    /// dedup at Stage C — different mechanism (exact string vs
    /// cosine) catches different failure modes.
    public static func dedupByCanonicalName(_ entities: [NormalisedEntity]) -> [NormalisedEntity] {
        struct Key: Hashable {
            let name: String
            let kind: Kind
        }
        var seenOrder: [Key] = []
        var bucket: [Key: NormalisedEntity] = [:]
        for ent in entities {
            let normName = ent.canonicalName.lowercased().trimmingCharacters(in: .whitespaces)
            let key = Key(name: normName, kind: ent.kind)
            if let existing = bucket[key] {
                let mergedAliases = Array(Set(existing.aliases + ent.aliases))
                bucket[key] = NormalisedEntity(
                    kind: existing.kind,
                    canonicalName: existing.canonicalName,
                    aliases: mergedAliases,
                    oneLine: existing.oneLine,
                    evidenceQuote: existing.evidenceQuote
                )
            } else {
                bucket[key] = ent
                seenOrder.append(key)
            }
        }
        return seenOrder.compactMap { bucket[$0] }
    }

    /// Titles + determiners that carry no identity — excluded when
    /// comparing a candidate alias against its canonical name, so
    /// "Miss Abby" and "Miss Megan" aren't treated as the same person.
    static let nameStopwords: Set<String> = [
        "the", "a", "an", "of", "and",
        "mr", "mrs", "ms", "miss", "dr", "doctor", "sir", "lady", "lord",
        "madam", "madame", "master", "mistress", "captain", "professor",
        "prof", "rev", "st", "saint",
    ]

    /// The significant (non-stopword) lowercased word tokens of a name.
    static func significantNameTokens(_ name: String) -> Set<String> {
        let tokens = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(tokens.map(String.init).filter { !nameStopwords.contains($0) })
    }

    /// Filter LLM-emitted aliases down to genuine surface variants of
    /// `canonicalName`.
    ///
    /// An alias survives only if it shares a significant word token
    /// with the canonical name (so "Dr. Thorn" is a valid alias of
    /// "Marius Thorn", but "Miss Abby" is not an alias of "Megan").
    /// This is structural enforcement against the LLM conflating
    /// distinct characters into one entity's alias list — observed on
    /// explicit prose, where gemma listed every name in the scene as
    /// an alias of whichever entity it was normalising. The alias that
    /// merely repeats the canonical name is dropped as redundant.
    public static func sanitizeAliases(_ aliases: [String], canonicalName: String) -> [String] {
        let canonTokens = significantNameTokens(canonicalName)
        let canonLower = canonicalName
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        var out: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower == canonLower || seen.contains(lower) { continue }
            guard !significantNameTokens(trimmed).isDisjoint(with: canonTokens) else { continue }
            seen.insert(lower)
            out.append(trimmed)
        }
        return out
    }

    public static func parseNormalisedEntity(_ raw: String) throws -> NormalisedEntity {
        guard let first = raw.firstIndex(of: "{") else {
            throw ParseError.noJSONObjectFound
        }
        // Find balanced closing brace from `first`.
        var depth = 0
        var end: String.Index?
        for i in raw[first...].indices {
            let c = raw[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
        }
        guard let last = end else { throw ParseError.malformedJSON }
        let slice = String(raw[first...last])
        struct R: Decodable {
            let kind: String?
            let canonical_name: String?
            let aliases: [String]?
            let one_line: String?
            let evidence_quote: String?
        }
        guard let data = slice.data(using: .utf8),
              let r = try? JSONDecoder().decode(R.self, from: data),
              let kRaw = r.kind, let kind = Kind(rawValue: kRaw),
              let name = r.canonical_name,
              let oneLine = r.one_line,
              let quote = r.evidence_quote
        else { throw ParseError.malformedJSON }
        return NormalisedEntity(
            kind: kind,
            canonicalName: name,
            aliases: sanitizeAliases(r.aliases ?? [], canonicalName: name),
            oneLine: oneLine,
            evidenceQuote: quote
        )
    }
}

/// Tokens that may lead a discovery output line as a bullet /
/// numbering marker the model adds unprompted. Stripped before
/// parsing — a real first field (a `kind` word or a character name)
/// starts with a letter, so this never eats meaningful content.
let lineLeadingNoiseCharacters: Set<Swift.Character> = [
    "-", "*", "•", ".", ")", " ", "\t",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
]

/// A `CodingKey` that accepts any string — lets the discovery
/// parsers probe several candidate field names for the same value
/// when the model emitted the JSON without a schema constraint.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
