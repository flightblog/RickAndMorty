import Foundation

/// Errors surfaced by `APIClient`. Kept small and specific so the UI layer
/// can react appropriately (e.g. show an empty state vs. a retry button)
/// instead of displaying a raw `Error.localizedDescription`.
enum APIError: Error, Equatable {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed
    case noResults
    case transport(String)

    var userMessage: String {
        switch self {
        case .invalidURL:
            return "Couldn't build a valid search request."
        case .requestFailed(let code):
            return "The server returned an unexpected response (\(code))."
        case .decodingFailed:
            return "Couldn't read the server's response."
        case .noResults:
            return "No characters match that search."
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}
