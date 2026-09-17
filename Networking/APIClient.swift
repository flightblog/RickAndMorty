import Foundation

/// Thin protocol over `URLSession` so tests can substitute a fake
/// networking layer (see `Tests/APIClientTests.swift`) without hitting
/// the real network or subclassing `URLSession` itself.
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

extension HTTPURLResponse {
    /// A 2xx status. Named here so both `APIClient` and `ImageLoader`
    /// agree on what "succeeded" means rather than each spelling out the
    /// same range.
    var isSuccessful: Bool { (200..<300).contains(statusCode) }
}

/// A small, generic client for the Rick and Morty API.
///
/// Everything here runs off the main thread (URLSession's async API
/// hops to a background context internally); callers on `@MainActor`
/// ViewModels simply `await` the result, so the UI never blocks.
final class APIClient {
    private let session: URLSessionProtocol
    private let baseURL = URL(string: "https://rickandmortyapi.com/api")!

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Fetches characters whose name contains `query`.
    ///
    /// - Parameter query: raw, unencoded search text typed by the user.
    /// - Throws: `APIError.noResults` for a 404 "nothing here" response,
    ///   `APIError.requestFailed` for other non-2xx responses,
    ///   `APIError.decodingFailed` if the payload shape is unexpected.
    func searchCharacters(named query: String) async throws -> [Character] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("character"),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        // URLComponents percent-encodes the query value for us, so spaces
        // and punctuation in what the user types can never produce a
        // malformed URL or break out of the query string.
        components.queryItems = [URLQueryItem(name: "name", value: query)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: URLRequest(url: url))
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: -1)
        }

        // The API uses 404 to mean "no matches" rather than "route missing",
        // so we translate that specific case into an empty-results error
        // the UI can treat as a normal empty state, not a failure banner.
        if http.statusCode == 404 {
            throw APIError.noResults
        }
        guard http.isSuccessful else {
            throw APIError.requestFailed(statusCode: http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(CharacterResponse.self, from: data)
            return decoded.results
        } catch {
            throw APIError.decodingFailed
        }
    }
}
