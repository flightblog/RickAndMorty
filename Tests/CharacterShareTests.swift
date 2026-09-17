import XCTest
import UniformTypeIdentifiers
@testable import RickAndMorty

final class CharacterShareTests: XCTestCase {

    // MARK: - shareSummary

    func testShareSummaryContainsEveryDisplayedField() {
        let summary = Character.fixture().shareSummary

        XCTAssertTrue(summary.contains("Rick Sanchez"))
        XCTAssertTrue(summary.contains("Species: Human"))
        XCTAssertTrue(summary.contains("Status: Alive"))
        XCTAssertTrue(summary.contains("Origin: Earth (C-137)"))
        XCTAssertTrue(summary.contains("Created: November 4, 2017"))
        XCTAssertTrue(summary.contains("avatar/1.jpeg"))
    }

    /// The detail view hides `type` when the API left it empty; a shared
    /// message must not contain a dangling "Type:" label either.
    func testShareSummaryOmitsTypeWhenEmpty() {
        XCTAssertFalse(Character.fixture(type: "").shareSummary.contains("Type:"))
    }

    func testShareSummaryIncludesTypeWhenPresent() {
        let summary = Character.fixture(type: "Genetic experiment").shareSummary
        XCTAssertTrue(summary.contains("Type: Genetic experiment"))
    }

    /// Guards the same fractional-seconds bug as `CharacterTests`: the
    /// shared text must not leak a raw ISO 8601 timestamp.
    func testShareSummaryUsesFormattedDateNotRawTimestamp() {
        let summary = Character.fixture().shareSummary
        XCTAssertFalse(summary.contains("2017-11-04T18:48:46.250Z"))
    }

    // MARK: - CharacterShareItem

    func testShareItemUsesServerMimeTypeOverURLExtension() throws {
        // URL says .jpeg, server says PNG — the server wins, so the
        // attachment isn't mislabelled.
        let item = try XCTUnwrap(
            CharacterShareItem(
                character: Character.fixture(),
                data: Data([0x89, 0x50]),
                mimeType: "image/png"
            )
        )

        XCTAssertEqual(item.contentType, .png)
        XCTAssertEqual(item.filename, "Rick Sanchez.png")
    }

    func testShareItemFallsBackToURLExtensionWhenMimeTypeMissing() throws {
        let item = try XCTUnwrap(
            CharacterShareItem(
                character: Character.fixture(),
                data: Data([0xFF, 0xD8]),
                mimeType: nil
            )
        )

        XCTAssertTrue(item.contentType.conforms(to: .image))
        XCTAssertEqual(item.filename, "Rick Sanchez.jpeg")
    }

    /// An HTML error page must never be handed to the share sheet
    /// labelled as a picture.
    func testShareItemIsNilForNonImageContentType() {
        XCTAssertNil(
            CharacterShareItem(
                character: Character.fixture(),
                data: Data("<html>nope</html>".utf8),
                mimeType: "text/html"
            )
        )
    }

    func testShareItemIsNilWhenTypeCannotBeResolved() {
        XCTAssertNil(
            CharacterShareItem(
                character: Character.fixture(imageURL: "https://example.com/avatar"),
                data: Data([0x00]),
                mimeType: nil
            )
        )
    }

    // MARK: - ImageLoader

    func testLoaderReturnsShareItemForSuccessfulImageResponse() async throws {
        let session = MockURLSession()
        session.data = Data([0xFF, 0xD8, 0xFF])
        session.mimeType = "image/jpeg"
        let loader = ImageLoader(session: session)

        let item = await loader.loadShareItem(for: Character.fixture())

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.imageData, Data([0xFF, 0xD8, 0xFF]))
    }

    func testLoaderReturnsNilOnHTTPError() async {
        let session = MockURLSession()
        session.statusCode = 404
        session.mimeType = "image/jpeg"
        let loader = ImageLoader(session: session)

        let item = await loader.loadShareItem(for: Character.fixture())

        XCTAssertNil(item, "A 404 body is not a shareable image")
    }

    /// A failed image fetch must degrade quietly to metadata-only
    /// sharing, never propagate an error into the UI.
    func testLoaderReturnsNilOnTransportErrorRatherThanThrowing() async {
        let session = MockURLSession()
        session.error = URLError(.notConnectedToInternet)
        let loader = ImageLoader(session: session)

        let item = await loader.loadShareItem(for: Character.fixture())

        XCTAssertNil(item)
    }
}
