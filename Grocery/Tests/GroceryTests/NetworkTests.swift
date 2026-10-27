import XCTest

/// Answers every request with whatever the current test set, so nothing reaches the internet.
final class StubProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var body = Data()
        var error: Error?
    }

    nonisolated(unsafe) static var reply = Reply()
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let error = Self.reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

class NetworkTestCase: XCTestCase {
    let session = StubProtocol.session()

    override func setUp() {
        super.setUp()
        StubProtocol.reply = .init()
        StubProtocol.requests = []
    }

    func reply(status: Int = 200, json: String) {
        StubProtocol.reply = .init(status: status, body: Data(json.utf8))
    }
}

final class ProductLookupTests: NetworkTestCase {
    func testAFoundProductBringsNameAisleSizeAndAllergens() async throws {
        reply(json: """
        {"product": {"product_name": " Nutella ", "categories_tags": ["en:sweet-spreads"], "quantity": "400 g",
                     "allergens_tags": ["en:milk", "en:nuts"], "ingredients_text": "Sugar, palm oil, hazelnuts, milk"}}
        """)
        let found = try await ProductLookup.product(for: "3017620422003", session: session)
        let product = try XCTUnwrap(found)
        XCTAssertEqual(product.name, "Nutella")
        XCTAssertEqual(product.aisle, .pantry)
        XCTAssertEqual(product.size, "400 g")
        XCTAssertEqual(product.allergens, ["en:milk", "en:nuts"])
        let request = try XCTUnwrap(StubProtocol.requests.first?.url)
        XCTAssertEqual(request.host(), "world.openfoodfacts.org")
        XCTAssertTrue(request.path().hasSuffix("/3017620422003.json"), "only the barcode is sent")
    }

    func testUnknownBarcodesAndEmptyNamesGiveNothing() async throws {
        reply(status: 404, json: #"{"status": 0}"#)
        let unknown = try await ProductLookup.product(for: "123", session: session)
        XCTAssertNil(unknown)
        reply(json: #"{"product": {"product_name": "   "}}"#)
        let blank = try await ProductLookup.product(for: "123", session: session)
        XCTAssertNil(blank)
        reply(json: #"{"status": 0}"#)
        let missing = try await ProductLookup.product(for: "123", session: session)
        XCTAssertNil(missing)
    }

    func testNonNumericCodesNeverReachTheNetwork() async throws {
        let result = try await ProductLookup.product(for: "abc/../etc", session: session)
        XCTAssertNil(result)
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func testOfflineAndGarbageAreErrors() async {
        StubProtocol.reply = .init(error: URLError(.notConnectedToInternet))
        await XCTAssertThrowsErrorAsync(try await ProductLookup.product(for: "123", session: session))
        reply(json: "<html>Service unavailable</html>")
        await XCTAssertThrowsErrorAsync(try await ProductLookup.product(for: "123", session: session))
    }
}

final class RecipeFetcherTests: NetworkTestCase {
    private let page = """
    <html><head><script type="application/ld+json">{"@type":"Recipe","name":"Weeknight Curry",
    "recipeIngredient":["2 tbsp oil","1 onion, diced","2 cups rice"]}</script></head></html>
    """

    func testARecipePageIsRead() async throws {
        reply(json: page)
        guard case .found(let recipe) = await RecipeFetcher.fetch(address: "example.com/curry", session: session) else {
            return XCTFail("expected a recipe")
        }
        XCTAssertEqual(recipe.name, "Weeknight Curry")
        XCTAssertEqual(recipe.lines, ["2 tbsp oil", "1 onion, diced", "2 cups rice"])
        XCTAssertEqual(StubProtocol.requests.first?.url?.absoluteString, "https://example.com/curry")
    }

    func testPagesWithoutARecipeAndErrorPages() async {
        reply(json: "<html><body>Just a blog post</body></html>")
        guard case .noRecipe = await RecipeFetcher.fetch(address: "https://example.com", session: session) else {
            return XCTFail("expected no recipe")
        }
        reply(status: 500, json: page)
        guard case .unreachable = await RecipeFetcher.fetch(address: "https://example.com", session: session) else {
            return XCTFail("a server error isn't a recipe")
        }
    }

    func testOfflineAndBadAddresses() async {
        StubProtocol.reply = .init(error: URLError(.notConnectedToInternet))
        guard case .unreachable = await RecipeFetcher.fetch(address: "https://example.com", session: session) else {
            return XCTFail("expected unreachable")
        }
        guard case .badAddress = await RecipeFetcher.fetch(address: "ftp://example.com", session: session) else {
            return XCTFail("expected a bad address")
        }
        XCTAssertEqual(StubProtocol.requests.count, 1, "the bad address never left the phone")
    }
}

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
