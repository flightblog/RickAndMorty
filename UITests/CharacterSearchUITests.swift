import XCTest

/// Drives the real app through the real API. Kept deliberately small and
/// tolerant of network latency — these verify the end-to-end wiring
/// (search field -> results -> detail), not exact content, since the
/// live API's data can change.
final class CharacterSearchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Tests run in alphabetical order and one of them rotates the
        // device; normalize before each so none inherits a rotated
        // (or still-rotating) screen.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    /// Focuses the search field and types into it.
    ///
    /// The first tap can land while the UI is still settling (a preceding
    /// test's rotation, or the search presentation animating), which
    /// leaves the field visible but unfocused and makes `typeText` fail
    /// with "no keyboard focus". Retrying the tap is far more reliable
    /// than a fixed sleep.
    private func search(for text: String) {
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        var focused = false
        for _ in 0..<3 {
            searchField.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
                focused = true
                break
            }
        }
        XCTAssertTrue(focused, "Search field never took keyboard focus")

        searchField.typeText(text)
    }

    private var searchField: XCUIElement {
        app.searchFields.firstMatch
    }

    /// The grid's cells. A `LazyVGrid` renders no `cells`, so these come
    /// back as buttons — matched on the identifier set in
    /// `CharacterListView` rather than on position, since the on-screen
    /// keyboard contributes buttons of its own.
    private var characterCells: XCUIElementQuery {
        app.buttons.matching(identifier: "character-cell")
    }

    private var firstCharacterCell: XCUIElement {
        characterCells.firstMatch
    }

    /// How many cells share the topmost row's Y origin — the effective
    /// column count at the current size.
    private func columnCount() -> Int {
        let frames = characterCells.allElementsBoundByIndex.map(\.frame)
        guard let topY = frames.map(\.minY).min() else { return 0 }
        return frames.filter { abs($0.minY - topY) < 1 }.count
    }

    func testEmptyStateIsShownBeforeAnySearch() {
        XCTAssertTrue(
            app.staticTexts["Find a character"].waitForExistence(timeout: 5),
            "Launch should show the pre-search empty state"
        )
    }

    func testTypingNameShowsMatchingCharacters() {
        search(for: "rick")

        // First cell should populate once the debounce + request complete.
        let firstCell = firstCharacterCell
        XCTAssertTrue(
            firstCell.waitForExistence(timeout: 15),
            "Searching 'rick' should produce at least one result row"
        )
        XCTAssertTrue(app.staticTexts["Rick Sanchez"].waitForExistence(timeout: 15))
    }

    func testTappingRowShowsDetailWithRequiredFields() {
        search(for: "rick sanchez")

        let firstCell = firstCharacterCell
        XCTAssertTrue(firstCell.waitForExistence(timeout: 15))
        firstCell.tap()

        // Every field the spec requires, except `type`, which is
        // conditional on the character actually having one.
        for label in ["Species", "Status", "Origin", "Created"] {
            XCTAssertTrue(
                app.staticTexts[label].waitForExistence(timeout: 10),
                "Detail view must show a \(label) field"
            )
        }
    }

    /// The created date must be rendered human-readably, not as the raw
    /// ISO 8601 string the API returns.
    func testDetailShowsFormattedCreatedDateNotRawISOString() {
        search(for: "rick sanchez")

        let firstCell = firstCharacterCell
        XCTAssertTrue(firstCell.waitForExistence(timeout: 15))
        firstCell.tap()

        // `DetailRow` combines its label and value into one element, so
        // the Created row reads as "Created, <date>". The inner "Created"
        // label stays separately queryable, so matching on the prefix
        // alone finds two elements and `element(matching:)` throws —
        // require the ", " that only the combined element carries.
        // Matching on the label works identically on iOS 17 and 26,
        // whereas an `.accessibilityIdentifier` on the combined element
        // proved unreliable on iOS 17.
        let createdRow = app.staticTexts.element(
            matching: NSPredicate(format: "label BEGINSWITH 'Created, '")
        )
        XCTAssertTrue(
            createdRow.waitForExistence(timeout: 20),
            "Detail view should show the Created row"
        )

        // The API sends "2017-11-04T18:48:46.250Z"; the view must render a
        // formatted date instead.
        let label = createdRow.label
        XCTAssertFalse(
            label.contains("T18:") || label.contains("Z"),
            "Created date is leaking the raw ISO 8601 timestamp: \(label)"
        )
        XCTAssertTrue(
            label.contains("2017"),
            "Expected a formatted 2017 date, got: \(label)"
        )
    }

    func testNoMatchesShowsEmptySearchState() {
        search(for: "zzzznotarealcharacter")

        // `ContentUnavailableView.search(text:)` renders the query into the
        // title, e.g. No Results for “zzzznotarealcharacter” — match on the
        // prefix rather than the full string, which carries smart quotes.
        let noResults = app.staticTexts.element(
            matching: NSPredicate(format: "label BEGINSWITH 'No Results'")
        )
        XCTAssertTrue(
            noResults.waitForExistence(timeout: 15),
            "A search with no matches should show the empty search state, not an error"
        )
        XCTAssertFalse(
            app.buttons["Retry"].exists,
            "A 404 no-match must not surface as an error banner"
        )
    }

    /// The happy path must not show the error banner. (The failure path
    /// is covered by `CharacterListViewModelTests.testRetry…`, which can
    /// simulate a server error without depending on real network
    /// conditions — something a UI test against the live API can't do
    /// reliably.)
    func testNoErrorBannerOnSuccessfulSearch() {
        search(for: "rick")

        XCTAssertTrue(firstCharacterCell.waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.buttons["Retry"].exists,
            "A successful search should not surface the error banner"
        )
    }

    /// The share button must be reachable from the detail view and must
    /// present the system share sheet.
    func testShareButtonPresentsShareSheet() {
        search(for: "rick sanchez")

        let firstCell = firstCharacterCell
        XCTAssertTrue(firstCell.waitForExistence(timeout: 15))
        firstCell.tap()

        let share = app.buttons["Share"]
        XCTAssertTrue(
            share.waitForExistence(timeout: 10),
            "Detail view should expose a Share button"
        )
        share.tap()

        // The activity sheet renders the preview title, so finding the
        // character name outside the navigation bar confirms it opened.
        let sheetAppeared = app.otherElements["ActivityListView"]
            .waitForExistence(timeout: 15)
            || app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(sheetAppeared, "Tapping Share should present the share sheet")
    }

    /// A search with many matches should lay out multiple cells (the grid
    /// puts more than one per row), and each cell should read as a single
    /// VoiceOver stop carrying both name and species.
    func testGridShowsMultipleCharactersWithCombinedAccessibilityLabels() {
        search(for: "rick")

        XCTAssertTrue(firstCharacterCell.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(
            characterCells.count, 1,
            "A broad search should fill the grid with several characters"
        )
        XCTAssertEqual(
            firstCharacterCell.label, "Rick Sanchez, Human",
            "Each cell should read as one stop with name and species combined"
        )
    }

    /// The grid uses `GridItem(.adaptive(...))` rather than a fixed column
    /// count, so it should fit more columns as the available width grows.
    func testGridReflowsToMoreColumnsInLandscape() {
        search(for: "rick")
        XCTAssertTrue(firstCharacterCell.waitForExistence(timeout: 15))

        XCUIDevice.shared.orientation = .portrait
        sleep(5)
        let portrait = columnCount()

        XCUIDevice.shared.orientation = .landscapeLeft
        // Rotation needs to settle before the frames are meaningful.
        sleep(8)
        let landscape = columnCount()

        XCUIDevice.shared.orientation = .portrait
        // Let the rotation finish inside this test rather than leaving it
        // in flight for whichever test runs next.
        sleep(5)

        XCTAssertGreaterThanOrEqual(portrait, 2, "Phone portrait should fit 2 columns")
        XCTAssertGreaterThan(
            landscape, portrait,
            "The adaptive grid should use the extra width in landscape"
        )
    }

    /// The zoom transition is configured by matching a `sourceID` on the
    /// cell to the pushed destination. There's no API to assert the
    /// animation's appearance, so this covers what is testable: tapping a
    /// cell other than the first still navigates to *that* character, so
    /// the per-character source IDs aren't crossed or shared.
    func testTappingANonFirstCellNavigatesToThatCharacter() {
        search(for: "rick")
        XCTAssertTrue(firstCharacterCell.waitForExistence(timeout: 15))

        let target = characterCells.element(boundBy: 3)
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        // The cell's combined label is "<name>, <species>".
        let name = String(target.label.split(separator: ",").first ?? "")
        XCTAssertFalse(name.isEmpty)

        target.tap()

        XCTAssertTrue(
            app.navigationBars[name].waitForExistence(timeout: 10),
            "Tapping the fourth cell should open \(name)'s detail view"
        )
    }
}
