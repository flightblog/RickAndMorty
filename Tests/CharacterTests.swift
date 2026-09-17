import XCTest
@testable import RickAndMorty

final class CharacterTests: XCTestCase {

    /// The API's `created` values carry fractional seconds, which
    /// `ISO8601DateFormatter` does not parse under its default options.
    /// This is the regression guard for that.
    func testCreatedDateParsesFractionalSecondsTimestamp() throws {
        let character = Character.fixture(created: "2017-11-04T18:48:46.250Z")

        let date = try XCTUnwrap(
            character.createdDate,
            "Fractional-seconds ISO 8601 timestamps must parse"
        )

        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: date
        )
        XCTAssertEqual(components.year, 2017)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 4)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 48)
        XCTAssertEqual(components.second, 46)
    }

    func testFormattedCreatedDateIsHumanReadable() {
        let character = Character.fixture(created: "2017-11-04T18:48:46.250Z")

        // Not asserting an exact string — that's locale-dependent. What
        // matters is that we no longer leak the raw ISO timestamp through.
        XCTAssertNotEqual(character.formattedCreatedDate, character.created)
        XCTAssertFalse(character.formattedCreatedDate.contains("T"))
        XCTAssertTrue(character.formattedCreatedDate.contains("2017"))
    }

    /// An unparseable timestamp should degrade to the raw string rather
    /// than crashing or rendering an empty field.
    func testFormattedCreatedDateFallsBackToRawStringWhenUnparseable() {
        let character = Character.fixture(created: "not a date")

        XCTAssertNil(character.createdDate)
        XCTAssertEqual(character.formattedCreatedDate, "not a date")
    }

    func testUnknownStatusDecodesToUnknownRatherThanFailing() throws {
        let json = #"{"id":1,"name":"X","status":"Transdimensional","species":"Human","type":"","origin":{"name":"Earth"},"image":"https://example.com/1.jpeg","created":"2017-11-04T18:48:46.250Z"}"#

        let character = try JSONDecoder().decode(Character.self, from: Data(json.utf8))

        XCTAssertEqual(character.status, .unknown)
    }
}
