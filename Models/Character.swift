import Foundation

/// A single character as returned by the Rick and Morty API.
///
/// `Identifiable` lets us use it directly in SwiftUI `List`/`ForEach`
/// without a separate wrapper type.
struct Character: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let status: Status
    let species: String
    /// Subspecies / variant, e.g. "Genetic experiment". Often empty.
    let type: String
    let origin: NamedLocation
    let image: URL
    /// ISO 8601 string from the API, e.g. "2017-11-04T18:48:46.250Z".
    let created: String

    enum Status: String, Codable, Hashable {
        case alive = "Alive"
        case dead = "Dead"
        case unknown = "unknown"

        /// Falls back to `.unknown` instead of failing to decode if the API
        /// ever adds a new status value we don't know about yet.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    struct NamedLocation: Codable, Hashable {
        let name: String
    }
}

extension Character {
    /// The API sends fractional seconds ("2017-11-04T18:48:46.250Z"), which
    /// `ISO8601DateFormatter`'s default options do *not* parse — hence the
    /// explicit `.withFractionalSeconds`. Held statically because formatter
    /// initialization is expensive and `createdDate` is read during list
    /// rendering, once per visible row per frame.
    private static let createdFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// The `created` timestamp parsed into a `Date`, or `nil` if the API
    /// ever returns something we don't recognize. Kept separate from the
    /// stored property so decoding never fails on a date-format surprise.
    var createdDate: Date? {
        Self.createdFormatter.date(from: created)
    }

    /// A user-facing, locale-aware rendering of `createdDate`.
    var formattedCreatedDate: String {
        guard let date = createdDate else { return created }
        return date.formatted(date: .long, time: .omitted)
    }

    /// A plain-text summary for sharing. Mirrors what the detail view
    /// shows, including omitting `type` when the API left it empty, so a
    /// shared message never contains a dangling "Type:" label.
    var shareSummary: String {
        var lines = [
            name,
            "Species: \(species)",
            "Status: \(status.rawValue)",
            "Origin: \(origin.name)",
        ]
        if !type.isEmpty {
            lines.append("Type: \(type)")
        }
        lines.append("Created: \(formattedCreatedDate)")
        lines.append(image.absoluteString)
        return lines.joined(separator: "\n")
    }
}
