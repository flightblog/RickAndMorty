import Foundation
import Observation

/// Drives `CharacterListView`.
///
/// Marked `@MainActor` so every mutation of observed state is guaranteed
/// to happen on the main thread (required for SwiftUI), while the actual
/// network call inside `search(for:)` is awaited off the main thread by
/// `APIClient`. This is what keeps typing responsive: the UI thread is
/// never blocked waiting on the network.
///
/// Uses the `@Observable` macro rather than `ObservableObject`: SwiftUI
/// then tracks reads at the property level, so a view that only reads
/// `characters` isn't invalidated when `isLoading` flips. Under
/// `ObservableObject` every `@Published` write notified the single
/// `objectWillChange` publisher and re-evaluated every observing view.
@MainActor
@Observable
final class CharacterListViewModel {
    var searchText: String = ""
    private(set) var characters: [Character] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    /// Injected rather than reached for as a singleton, so tests can
    /// substitute a client backed by a fake `URLSession`.
    private let apiClient: APIClient
    /// Debounce window: avoids firing a network request on every single
    /// keystroke while the user is still typing.
    private let debounceNanoseconds: UInt64

    /// The query behind whatever is currently on screen. `retry()` reuses
    /// it so a failed search can be repeated without the user retyping.
    private var lastAttemptedQuery: String?

    init(apiClient: APIClient = APIClient(), debounceMilliseconds: UInt64 = 300) {
        self.apiClient = apiClient
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
    }

    /// Called from the view via `.task(id: searchText) { await viewModel.search(for: searchText) }`.
    /// SwiftUI automatically cancels the previous in-flight `Task` when
    /// `searchText` changes again, so a fast typist never sees a stale,
    /// out-of-order result overwrite a newer one.
    func search(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear results for an empty search rather than calling the API
        // with an empty `name`, which would return the entire (paginated)
        // character list — not what an empty search bar should show.
        guard !trimmed.isEmpty else {
            lastAttemptedQuery = nil
            characters = []
            errorMessage = nil
            isLoading = false
            return
        }

        await performSearch(for: trimmed, debounced: true)
    }

    /// Re-runs the last search that was attempted. Bound to the retry
    /// button on the error state so a transient network failure doesn't
    /// cost the user their typing.
    func retry() async {
        guard let query = lastAttemptedQuery else { return }
        await performSearch(for: query, debounced: false)
    }

    /// What a search settled on, decided before any state is touched so
    /// the cancellation check can guard every path in one place.
    private enum Outcome {
        case results([Character])
        case failure(String)
    }

    /// - Parameters:
    ///   - query: already trimmed and known non-empty.
    ///   - debounced: `false` for an explicit user action like retry,
    ///     where waiting out the keystroke debounce would just feel slow.
    private func performSearch(for query: String, debounced: Bool) async {
        lastAttemptedQuery = query

        // Set before the debounce, not after: the view re-runs this method on
        // every keystroke via `.task(id:)`, so a spinner that only appears
        // once the sleep completes would never show while the user is typing.
        isLoading = true
        errorMessage = nil
        // Always clear the flag on the way out, including on cancellation. A
        // cancelled task's successor immediately sets it back to `true`, so
        // clearing it here can't hide a real in-flight request — whereas
        // skipping the clear can strand the spinner on with no owning task.
        defer { isLoading = false }

        if debounced {
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return // cancelled by a newer keystroke; do nothing
            }
            guard !Task.isCancelled else { return }
        }

        // Resolve the outcome first, then apply it behind a single
        // cancellation check: a newer keystroke's task is already on its
        // way, so a stale result must not overwrite what it will set.
        let outcome: Outcome
        do {
            outcome = .results(try await apiClient.searchCharacters(named: query))
        } catch APIError.noResults {
            outcome = .results([])
        } catch {
            outcome = .failure((error as? APIError)?.userMessage ?? error.localizedDescription)
        }

        guard !Task.isCancelled else { return }

        switch outcome {
        case .results(let results):
            characters = results
        // Deliberately leaves `characters` untouched: a transient failure
        // shouldn't wipe results the user can still read and scroll. The
        // view shows the error alongside them.
        case .failure(let message):
            errorMessage = message
        }
    }
}
