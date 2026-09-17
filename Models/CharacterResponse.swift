import Foundation

/// Top-level shape of `GET /api/character?name=...`.
///
/// The payload also carries an `info` object (result count, page count),
/// omitted here because nothing reads it — `Decodable` ignores unknown
/// keys, so leaving it out costs nothing and adds no pagination code
/// this app doesn't use.
struct CharacterResponse: Codable {
    let results: [Character]
}
