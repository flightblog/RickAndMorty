import XCTest
@testable import RickAndMorty

@MainActor
final class CharacterListViewModelTests: XCTestCase {

    private let sampleJSON = """
    {
      "info": { "count": 1, "pages": 1 },
      "results": [
        {
          "id": 2,
          "name": "Morty Smith",
          "status": "Alive",
          "species": "Human",
          "type": "",
          "origin": { "name": "Earth (C-137)" },
          "image": "https://rickandmortyapi.com/api/character/avatar/2.jpeg",
          "created": "2017-11-04T18:50:21.651Z"
        }
      ]
    }
    """

    func testEmptyQueryClearsResultsWithoutCallingAPI() async {
        let session = MockURLSession()
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "")

        XCTAssertTrue(viewModel.characters.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSuccessfulSearchPopulatesCharactersAndClearsLoading() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        session.statusCode = 200
        // Zero debounce so the test runs instantly instead of waiting
        // on the production 300ms UX delay.
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "morty")

        XCTAssertEqual(viewModel.characters.count, 1)
        XCTAssertEqual(viewModel.characters.first?.name, "Morty Smith")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testNoResultsProducesEmptyListNotAnError() async {
        let session = MockURLSession()
        session.data = Data(#"{"error":"There is nothing here"}"#.utf8)
        session.statusCode = 404
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "zzzznotarealname")

        XCTAssertTrue(viewModel.characters.isEmpty)
        // A 404 "no matches" is a normal empty state, not a user-facing
        // error banner.
        XCTAssertNil(viewModel.errorMessage)
    }

    /// Regression guard: `isLoading` must be set *before* the debounce
    /// sleep, otherwise the spinner never appears while the user is
    /// actively typing (every keystroke cancels the task mid-sleep).
    func testIsLoadingBecomesTrueDuringDebounceWindow() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 200
        )

        let task = Task { await viewModel.search(for: "morty") }
        // Yield long enough to enter the debounce but not to clear it.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(
            viewModel.isLoading,
            "Spinner should be visible during the debounce window, not just the request"
        )

        await task.value
        XCTAssertFalse(viewModel.isLoading)
    }

    /// Regression guard: a cancelled search must not strand `isLoading`
    /// at `true`. Previously the flag was skipped on the cancellation
    /// path, so a task cancelled mid-flight left the spinner stuck on.
    func testCancellationClearsIsLoading() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 500
        )

        let task = Task { await viewModel.search(for: "morty") }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(viewModel.isLoading)

        task.cancel()
        await task.value

        XCTAssertFalse(
            viewModel.isLoading,
            "A cancelled search must leave isLoading false, not stranded true"
        )
    }

    func testEmptyQueryMakesNoNetworkRequest() async {
        let session = MockURLSession()
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "   ")

        XCTAssertTrue(session.requestedURLs.isEmpty)
        XCTAssertTrue(viewModel.characters.isEmpty)
    }

    func testSearchTextIsPercentEncodedIntoNameQueryItem() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "rick & morty")

        let url = try? XCTUnwrap(session.requestedURLs.first)
        XCTAssertEqual(
            url?.query,
            "name=rick%20%26%20morty",
            "Ampersands must be encoded, not treated as a query separator"
        )
    }

    func testServerErrorSetsErrorMessage() async {
        let session = MockURLSession()
        session.statusCode = 500
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "rick")

        XCTAssertTrue(viewModel.characters.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// A failed refresh must not discard results the user can still read.
    func testErrorPreservesPreviouslyLoadedResults() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "morty")
        XCTAssertEqual(viewModel.characters.count, 1)

        session.statusCode = 500
        await viewModel.search(for: "mortyy")

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(
            viewModel.characters.count, 1,
            "A transient failure should leave existing results on screen"
        )
    }

    func testRetryReissuesLastQueryAndClearsErrorOnSuccess() async {
        let session = MockURLSession()
        session.statusCode = 500
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "morty")
        XCTAssertNotNil(viewModel.errorMessage)

        // Network recovers; retry should re-run "morty" without the
        // caller having to supply it again.
        session.statusCode = 200
        session.data = Data(sampleJSON.utf8)
        await viewModel.retry()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.characters.first?.name, "Morty Smith")
        XCTAssertEqual(session.requestedURLs.count, 2)
        XCTAssertEqual(session.requestedURLs.last?.query, "name=morty")
    }

    func testRetryIsANoOpWhenNothingHasBeenSearched() async {
        let session = MockURLSession()
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.retry()

        XCTAssertTrue(session.requestedURLs.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    /// Whitespace-only input is treated as empty, and surrounding
    /// whitespace is trimmed off before it reaches the query string.
    func testQueryIsTrimmedBeforeBeingSentToTheAPI() async {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "  morty\n")

        XCTAssertEqual(session.requestedURLs.first?.query, "name=morty")
    }

    func testNewlineOnlyQueryMakesNoNetworkRequest() async {
        let session = MockURLSession()
        let viewModel = CharacterListViewModel(
            apiClient: APIClient(session: session),
            debounceMilliseconds: 0
        )

        await viewModel.search(for: "\n\t ")

        XCTAssertTrue(session.requestedURLs.isEmpty)
    }
}
