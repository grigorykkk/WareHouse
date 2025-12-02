import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

private struct WarehouseSummaryResponse: Decodable {
    let id: Int
    let type: String
    let address: String
    let capacity: Double
    let freeVolume: Double
    let usedVolume: Double
    let productKindsCount: Int
}

private struct InventoryItemResponse: Decodable {
    let productId: Int
    let name: String
    let quantity: Int
    let unitVolume: Double
    let totalVolume: Double
    let unitPrice: Double
    let totalCost: Double
    let shelfLifeDays: Int
    let supplierId: Int
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
    private let logDateFormatter: DateFormatter

    init(configuration: AppConfiguration, logger: AppLogger, session: URLSession? = nil) {
        self.configuration = configuration
        self.logger = logger
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.logDateFormatter = formatter

        self.session = session ?? URLSession(configuration: .default)
        self.customSessionProvided = session != nil
        if !customSessionProvided {
            configureSession()
        }
    }

    func fetchWarehouses() async throws -> [Warehouse] {
        let endpoint = APIEndpoint(path: "/api/warehouses")
        let response: [WarehouseSummaryResponse] = try await request(endpoint)
        return response.map(mapWarehouse)
    }

    func fetchInventory(for warehouseId: Int) async throws -> [InventoryItem] {
        let endpoint = APIEndpoint(path: "/api/warehouses/\(warehouseId)/inventory")
        let response: [InventoryItemResponse] = try await request(endpoint)
        return response.map(mapInventoryItem)
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

    func runAnalysis() async throws -> AnalysisResult {
        let endpoint = APIEndpoint(path: "/api/analysis")
        let entries: [AnalysisEntry] = try await request(endpoint)
        return AnalysisResult.aggregate(from: entries)
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
        let response: [String] = try await request(endpoint)
        return response.map(parseLogEntry)
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
        if let plain = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }
        return nil
    }

    private func mapWarehouse(_ dto: WarehouseSummaryResponse) -> Warehouse {
        Warehouse(id: dto.id,
                  name: "Склад \(dto.id) (\(dto.type))",
                  address: dto.address,
                  type: dto.type,
                  capacity: dto.capacity,
                  occupiedVolume: dto.usedVolume,
                  freeVolume: dto.freeVolume,
                  hasIssues: nil,
                  needsSortingOptimization: nil,
                  needsExpiredRemoval: nil,
                  needsTypeCorrection: nil,
                  productKindsCount: dto.productKindsCount)
    }

    private func mapInventoryItem(_ dto: InventoryItemResponse) -> InventoryItem {
        let totalVolume = dto.totalVolume > 0 ? dto.totalVolume : dto.unitVolume * Double(dto.quantity)
        let totalPrice = dto.totalCost > 0 ? dto.totalCost : dto.unitPrice * Double(dto.quantity)
        return InventoryItem(id: dto.productId,
                             productId: dto.productId,
                             supplierId: dto.supplierId,
                             name: dto.name,
                             unitVolume: dto.unitVolume,
                             unitPrice: dto.unitPrice,
                             shelfLifeDays: dto.shelfLifeDays,
                             quantity: dto.quantity,
                             totalVolume: totalVolume,
                             totalPrice: totalPrice,
                             isExpired: dto.shelfLifeDays <= 0,
                             type: nil)
    }

    private func parseLogEntry(_ raw: String) -> AuditLogEntry {
        let timestampLength = 19 // "yyyy-MM-dd HH:mm:ss"
        let separator = raw.range(of: ": ")
        let timestampPart = separator.map { String(raw[..<$0.lowerBound]) } ?? String(raw.prefix(timestampLength))
        let startIndex = separator?.upperBound ?? raw.index(raw.startIndex, offsetBy: min(raw.count, timestampLength))
        let message = raw[startIndex...].trimmingCharacters(in: .whitespaces)
        let date = logDateFormatter.date(from: timestampPart) ?? Date()
        let deltas = parseInventoryDelta(from: message)
        let ids = parseWarehouseIds(from: message)
        let lowercased = message.lowercased()
        let operation: String
        if lowercased.contains("поставка") {
            operation = "Supply"
        } else if message.contains("->") {
            operation = "Transfer"
        } else {
            operation = "Log"
        }
        return AuditLogEntry(id: UUID(),
                             timestamp: date,
                             message: message,
                             sourceWarehouseId: ids.0,
                             targetWarehouseId: ids.1,
                             operationType: operation,
                             changedItems: deltas)
    }

    private func parseInventoryDelta(from message: String) -> [InventoryDelta] {
        guard let segment = message.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return []
        }
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: " x") else { return [] }
        let name = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let quantityText = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let quantity = Int(quantityText), !name.isEmpty else {
            return []
        }
        return [InventoryDelta(id: UUID(), productId: 0, name: String(name), quantityChange: quantity)]
    }

    private func parseWarehouseIds(from message: String) -> (Int?, Int?) {
        guard let regex = try? NSRegularExpression(pattern: #"Склад (\d+)"#, options: []) else {
            return (nil, nil)
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = regex.matches(in: message, range: range)
        let ids: [Int] = matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: message) else { return nil }
            return Int(message[range])
        }
        return (ids.first, ids.count > 1 ? ids[1] : nil)
    }
}
