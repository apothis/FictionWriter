import Foundation

/// Loom's standard JSON coders. Pretty + sorted output for diff-friendly
/// on-disk files; ISO-8601 with fractional seconds on encode so `Date`
/// values round-trip with millisecond precision (Foundation's default
/// `.iso8601` strategy truncates to whole seconds, breaking equality on
/// round-trip). Decoding tolerates both fractional and non-fractional
/// forms — handwritten / external-editor JSON might use plain
/// `2026-01-01T00:00:00Z`.
extension JSONEncoder {
    public static var loomPretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(LoomISO8601.fractionalFormatter.string(from: date))
        }
        return e
    }
}

extension JSONDecoder {
    public static var loom: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = LoomISO8601.fractionalFormatter.date(from: s) {
                return date
            }
            if let date = LoomISO8601.plainFormatter.date(from: s) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Date string does not match ISO-8601 with optional fractional seconds: \(s)"
            )
        }
        return d
    }
}

enum LoomISO8601 {
    static let fractionalFormatter: DateFormatter = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    static let plainFormatter: DateFormatter = makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    /// Canonicalise a Date so round-trip through the fractional-second
    /// encoder is identity. We do this by printing-then-parsing through
    /// the formatter itself: the result is the same bit pattern the
    /// decoder will produce when reading the encoded string. Use this
    /// anywhere a Date is captured for persistence (Project.createdAt,
    /// GeneratedSpan.generatedAt, KnownFact.addedAt, Snapshot.takenAt).
    static func roundedToMillisecond(_ date: Date) -> Date {
        let s = fractionalFormatter.string(from: date)
        return fractionalFormatter.date(from: s) ?? date
    }
}
