import Foundation
@testable import RickAndMorty

/// A fake `URLSessionProtocol` conformer so tests never touch the real
/// network: fast, deterministic, and works offline/in CI.
///
/// Lives in its own file because both `APIClientTests` and
/// `CharacterListViewModelTests` depend on it.
final class MockURLSession: URLSessionProtocol {
    var data: Data = Data()
    var statusCode: Int = 200
    var error: Error?
    /// Sent back as the response's `Content-Type`, which `ImageLoader`
    /// uses to decide whether the payload is really an image.
    var mimeType: String?

    /// Every URL this mock was asked for, in order — lets a test assert
    /// that no request was made at all, or that the query was built right.
    private(set) var requestedURLs: [URL] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url {
            requestedURLs.append(url)
        }
        if let error {
            throw error
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: mimeType.map { ["Content-Type": $0] }
              ) else {
            throw URLError(.badURL)
        }
        return (data, response)
    }
}
