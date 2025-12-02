import XCTest
@testable import WareHouse_App

@MainActor
final class WarehouseAPITests: XCTestCase {
    private var api: WarehouseAPI!
    private var logger: AppLogger!

    override func setUp() {
        super.setUp()
        logger = AppLogger()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        api = WarehouseAPI(configuration: AppConfiguration(baseURL: URL(string: "https://example.com")!,
                                                          token: "test-token"),
                           logger: logger,
                           session: session)
    }

    override func tearDown() {
        api = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchWarehousesDecodesList() async throws {
        let body = """
        [
          { "id": 1, "type": "General", "address": "Main st", "capacity": 1000, "freeVolume": 800, "usedVolume": 200, "productKindsCount": 3 },
          { "id": 2, "type": "Cold", "address": "Backup", "capacity": 500, "freeVolume": 400, "usedVolume": 100, "productKindsCount": 2 }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, body)
        }

        let warehouses = try await api.fetchWarehouses()
        let first = try XCTUnwrap(warehouses.first)
        XCTAssertEqual(warehouses.count, 2)
        XCTAssertEqual(first.name, "Склад 1 (General)")
        XCTAssertEqual(first.address, "Main st")
        XCTAssertEqual(first.fillRate, 0.2, accuracy: 0.01)
    }

    func testServerErrorPropagatesValidationMessage() async {
        let errorBody = """
        { "message": "Capacity exceeded", "details": ["Too many pallets"] }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 400,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, errorBody)
        }

        let request = SupplyRequest(items: [])
        do {
            _ = try await api.createSupply(request)
            XCTFail("Expected to throw")
        } catch let error as APIError {
            switch error {
            case .server(let status, let message):
                XCTAssertEqual(status, 400)
                XCTAssertTrue(message.contains("Capacity"))
            default:
                XCTFail("Unexpected error \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testAuthorizationHeaderIsAttached() async throws {
        let expectation = expectation(description: "Authorization header added")

        MockURLProtocol.requestHandler = { request in
            if let header = request.value(forHTTPHeaderField: "Authorization") {
                XCTAssertEqual(header, "Bearer test-token")
                expectation.fulfill()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, "[]".data(using: .utf8)!)
        }

        _ = try? await api.fetchWarehouses()
        await fulfillment(of: [expectation], timeout: 1)
    }
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "NoHandler", code: 0))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
