import Foundation

/// Fetches the bytes behind a character's image so they can be shared.
/// Injectable so the detail view's tests never touch the network.
protocol ImageLoading: Sendable {
    func loadShareItem(for character: Character) async -> CharacterShareItem?
}

/// Default implementation, backed by `URLSession`'s shared cache so this
/// request is typically served from memory — `AsyncImage` has usually
/// already fetched the same URL to draw the picture on screen.
struct ImageLoader: ImageLoading {
    private let session: URLSessionProtocol

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func loadShareItem(for character: Character) async -> CharacterShareItem? {
        do {
            let (data, response) = try await session.data(
                for: URLRequest(url: character.image)
            )
            // A non-2xx body is an error page, not a picture.
            if let http = response as? HTTPURLResponse, !http.isSuccessful {
                return nil
            }
            return CharacterShareItem(
                character: character,
                data: data,
                mimeType: response.mimeType
            )
        } catch {
            // Sharing the image is a convenience; failing to load it
            // should degrade to metadata-only sharing, never surface an
            // error or block the screen.
            return nil
        }
    }
}
