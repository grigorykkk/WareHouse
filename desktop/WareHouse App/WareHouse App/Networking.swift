import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

struct APIEndpoint {
    var path: String
    var method: HTTPMethod = .get
    var body: Data? = nil
    var queryItems: [URLQueryItem] = []
}

final class WarehouseAPI {
    var configuration: AppConfiguration {
        didSet {
            if !customSessionProvided {
                configureSession()
            }
        }
    }

    private(set) var session: URLSession
    private let logger: AppLogger
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let customSessionProvided: Bool

    init(configuration: AppConfiguration, logger: AppLogger, session: URLSession? = nil) {
        self.configuration = configuration
        self.logger = logger
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        self.session = session ?? URLSession(configuration: .default)
        self.customSessionProvided = session != nil
        if !customSessionProvided {
            configureSession()
        }
    }

    func fetchWarehouses() async throws -> [Warehouse] {
        let endpoint = APIEndpoint(path: "/api/warehouses")
        return try await request(endpoint)
    }

    func fetchInventory(for warehouseId: Int) async throws -> [InventoryItem] {
        let endpoint = APIEndpoint(path: "/api/warehouses/\(warehouseId)/inventory")
        return try await request(endpoint)
    }

    func createSupply(_ supply: SupplyRequest) async throws -> SupplyResponse {
        let data = try encoder.encode(supply)
        let endpoint = APIEndpoint(path: "/api/supplies", method: .post, body: data)
        return try await request(endpoint)
    }

    func createTransfer(_ transfer: TransferRequest) async throws -> TransferResponse {
        let data = try encoder.encode(transfer)
        let endpoint = APIEndpoint(path: "/api/transfers", method: .post, body: data)
        return try await request(endpoint)
    }

    func runAnalysis(request: AnalysisRequest? = nil) async throws -> AnalysisResult {
        let payload = request ?? AnalysisRequest(warehouseIds: nil)
        let data = try encoder.encode(payload)
        let endpoint = APIEndpoint(path: "/api/analysis", method: .post, body: data)
        return try await request(endpoint)
    }

    func fetchLogs(query: LogQuery) async throws -> [AuditLogEntry] {
        var items: [URLQueryItem] = []
        if let warehouseId = query.warehouseId {
            items.append(URLQueryItem(name: "warehouseId", value: "\(warehouseId)"))
        }
        if let operationType = query.operationType {
            items.append(URLQueryItem(name: "operationType", value: operationType))
        }
        if let range = query.dateRange {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "from", value: formatter.string(from: range.lowerBound)))
            items.append(URLQueryItem(name: "to", value: formatter.string(from: range.upperBound)))
        }
        let endpoint = APIEndpoint(path: "/api/logs", queryItems: items)
        return try await request(endpoint)
    }

    // MARK: - Private

    private func configureSession() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    private func makeURL(for endpoint: APIEndpoint) -> URL? {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: true)
        components?.path = endpoint.path
        if !endpoint.queryItems.isEmpty {
            components?.queryItems = endpoint.queryItems
        }
        return components?.url
    }

    private func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        guard let url = makeURL(for: endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        if let token = configuration.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if endpoint.body != nil {
            request.httpBody = endpoint.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.decoding
            }
            if !(200...299).contains(httpResponse.statusCode) {
                let message = try decodeServerMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                logger.log("Server error \(httpResponse.statusCode): \(message)")
                throw APIError.server(status: httpResponse.statusCode, message: message)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.log("Decoding error: \(error.localizedDescription)")
                throw APIError.decoding
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            logger.log("Transport error: \(error.localizedDescription)")
            throw APIError.offline(message: "Нет соединения с сервером.")
        }
    }

    private func decodeServerMessage(_ data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }
        if let error = try? decoder.decode(ServerErrorResponse.self, from: data) {
            if let details = error.details, !details.isEmpty {
                return ([error.message] + details).joined(separator: "\n")
            }
            return error.message
        }
        return nil
    }
}
