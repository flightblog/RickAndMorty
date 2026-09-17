import XCTest
@testable import RickAndMorty

final class APIClientTests: XCTestCase {

    private let sampleJSON = """
    {
      "info": { "count": 1, "pages": 1 },
      "results": [
        {
          "id": 1,
          "name": "Rick Sanchez",
          "status": "Alive",
          "species": "Human",
          "type": "",
          "origin": { "name": "Earth (C-137)" },
          "image": "https://rickandmortyapi.com/api/character/avatar/1.jpeg",
          "created": "2017-11-04T18:48:46.250Z"
        }
      ]
    }
    """

    func testSearchCharactersDecodesSuccessResponse() async throws {
        let session = MockURLSession()
        session.data = Data(sampleJSON.utf8)
        session.statusCode = 200
        let client = APIClient(session: session)

        let results = try await client.searchCharacters(named: "rick")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Rick Sanchez")
        XCTAssertEqual(results.first?.status, .alive)
        XCTAssertEqual(results.first?.origin.name, "Earth (C-137)")
    }

    func testSearchCharactersThrowsNoResultsOn404() async {
        let session = MockURLSession()
        session.data = Data(#"{"error":"There is nothing here"}"#.utf8)
        session.statusCode = 404
        let client = APIClient(session: session)

        do {
            _ = try await client.searchCharacters(named: "zzzznotarealname")
            XCTFail("Expected APIError.noResults to be thrown")
        } catch APIError.noResults {
            // expected
        } catch {
            XCTFail("Expected .noResults, got \(error)")
        }
    }

    func testSearchCharactersThrowsDecodingFailedOnMalformedJSON() async {
        let session = MockURLSession()
        session.data = Data(#"{"unexpected":"shape"}"#.utf8)
        session.statusCode = 200
        let client = APIClient(session: session)

        do {
            _ = try await client.searchCharacters(named: "rick")
            XCTFail("Expected APIError.decodingFailed to be thrown")
        } catch APIError.decodingFailed {
            // expected
        } catch {
            XCTFail("Expected .decodingFailed, got \(error)")
        }
    }

    func testSearchCharactersThrowsRequestFailedOnServerError() async {
        let session = MockURLSession()
        session.data = Data()
        session.statusCode = 500
        let client = APIClient(session: session)

        do {
            _ = try await client.searchCharacters(named: "rick")
            XCTFail("Expected APIError.requestFailed to be thrown")
        } catch APIError.requestFailed(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected .requestFailed, got \(error)")
        }
    }
}
