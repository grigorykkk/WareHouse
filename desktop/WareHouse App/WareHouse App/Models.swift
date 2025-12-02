import Foundation

// MARK: - Core models

struct Warehouse: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    var name: String
    var address: String? = nil
    var type: String? = nil
    var capacity: Double
    var occupiedVolume: Double
    var freeVolume: Double? = nil
    var hasIssues: Bool? = nil
    var needsSortingOptimization: Bool? = nil
    var needsExpiredRemoval: Bool? = nil
    var needsTypeCorrection: Bool? = nil
    var productKindsCount: Int? = nil

    var fillRate: Double {
        guard capacity > 0 else { return 0 }
        let used = freeVolume.map { capacity - $0 } ?? occupiedVolume
        return used / capacity
    }

    var remainingVolume: Double {
        if let freeVolume {
            return max(freeVolume, 0)
        }
        return max(capacity - occupiedVolume, 0)
    }
}

struct InventoryItem: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    var productId: Int
    var supplierId: Int
    var name: String
    var unitVolume: Double
    var unitPrice: Double
    var shelfLifeDays: Int
    var quantity: Int
    var totalVolume: Double = 0
    var totalPrice: Double = 0
    var isExpired: Bool? = nil
    var type: String? = nil
}

struct SupplyItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var productId: Int
    var supplierId: Int
    var name: String
    var unitVolume: Double
    var unitPrice: Double
    var shelfLifeDays: Int
    var quantity: Int

    init(id: UUID = UUID(),
         productId: Int = 0,
         supplierId: Int = 0,
         name: String = "",
         unitVolume: Double = 0,
         unitPrice: Double = 0,
         shelfLifeDays: Int = 0,
         quantity: Int = 0) {
        self.id = id
        self.productId = productId
        self.supplierId = supplierId
        self.name = name
        self.unitVolume = unitVolume
        self.unitPrice = unitPrice
        self.shelfLifeDays = shelfLifeDays
        self.quantity = quantity
    }

    var asRequestItem: SupplyRequest.Item {
        SupplyRequest.Item(productId: productId,
                           supplierId: supplierId,
                           name: name,
                           unitVolume: unitVolume,
                           unitPrice: unitPrice,
                           shelfLifeDays: shelfLifeDays,
                           quantity: quantity)
    }
}

struct TransferItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var productId: Int
    var name: String
    var quantity: Int

    init(id: UUID = UUID(), productId: Int = 0, name: String = "", quantity: Int = 0) {
        self.id = id
        self.productId = productId
        self.name = name
        self.quantity = quantity
    }

    var asRequestItem: TransferRequest.Item {
        TransferRequest.Item(productId: productId, quantity: quantity)
    }
}

// MARK: - Requests / Responses

struct SupplyRequest: Codable {
    var items: [Item]

    struct Item: Codable {
        var productId: Int
        var supplierId: Int
        var name: String
        var unitVolume: Double
        var unitPrice: Double
        var shelfLifeDays: Int
        var quantity: Int
    }
}

struct SupplyResponse: Codable {
    var fullyPlaced: Bool
}

struct TransferRequest: Codable {
    var sourceWarehouseId: Int
    var destinationWarehouseId: Int
    var items: [Item]

    struct Item: Codable {
        var productId: Int
        var quantity: Int
    }
}

struct TransferResponse: Codable {
    var moved: Bool
}

struct AnalysisEntry: Codable, Equatable, Hashable {
    var warehouseId: Int
    var address: String?
    var hasIssues: Bool
    var needsSortingOptimization: Bool
    var needsExpiredRemoval: Bool
    var needsTypeCorrection: Bool
    var usedVolume: Double
    var freeVolume: Double
    var comment: String?
}

struct AnalysisResult: Codable, Equatable, Hashable {
    var hasIssues: Bool
    var needsSortingOptimization: Bool
    var needsExpiredRemoval: Bool
    var needsTypeCorrection: Bool
    var entries: [AnalysisEntry]? = nil
    var problemWarehouseIds: [Int]? = nil
}

extension AnalysisResult {
    static func aggregate(from entries: [AnalysisEntry]) -> AnalysisResult {
        let problems = entries
            .filter { $0.hasIssues || $0.needsExpiredRemoval || $0.needsSortingOptimization || $0.needsTypeCorrection }
            .map { $0.warehouseId }

        return AnalysisResult(hasIssues: entries.contains { $0.hasIssues },
                              needsSortingOptimization: entries.contains { $0.needsSortingOptimization },
                              needsExpiredRemoval: entries.contains { $0.needsExpiredRemoval },
                              needsTypeCorrection: entries.contains { $0.needsTypeCorrection },
                              entries: entries,
                              problemWarehouseIds: problems.isEmpty ? nil : problems)
    }
}

struct AuditLogEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var timestamp: Date
    var message: String = ""
    var sourceWarehouseId: Int?
    var targetWarehouseId: Int?
    var operationType: String = ""
    var changedItems: [InventoryDelta] = []
}

struct InventoryDelta: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var productId: Int
    var name: String
    var quantityChange: Int
}

// MARK: - Filtering models

struct LogQuery: Codable, Equatable {
    var warehouseId: Int?
    var operationType: String?
    var dateRange: ClosedRange<Date>?
}

// MARK: - Cache

struct CachedEntry<T: Codable>: Codable {
    var timestamp: Date
    var value: T
}

enum CacheKey: Hashable {
    case warehouses
    case inventory(Int)
    case analysis
    case logs

    var rawValue: String {
        switch self {
        case .warehouses:
            return "warehouses"
        case .inventory(let id):
            return "inventory-\(id)"
        case .analysis:
            return "analysis"
        case .logs:
            return "logs"
        }
    }
}

// MARK: - Errors

struct ServerErrorResponse: Codable {
    var message: String
    var details: [String]?
}

enum APIError: LocalizedError {
    case invalidURL
    case decoding
    case server(status: Int, message: String)
    case offline(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный адрес сервера."
        case .decoding:
            return "Не удалось обработать ответ сервера."
        case .server(let status, let message):
            return "Ошибка \(status): \(message)"
        case .offline(let message):
            return message
        }
    }
}

// MARK: - Sample data for previews/tests

extension Warehouse {
    static let sample = Warehouse(id: 1,
                                  name: "Main Hub",
                                  address: "Industrial Ave, 12",
                                  type: "General",
                                  capacity: 10_000,
                                  occupiedVolume: 6_200,
                                  freeVolume: 3_800,
                                  hasIssues: true,
                                  needsSortingOptimization: true,
                                  needsExpiredRemoval: false,
                                  needsTypeCorrection: false,
                                  productKindsCount: 4)
}

extension InventoryItem {
    static let sample = InventoryItem(id: 1,
                                      productId: 101,
                                      supplierId: 11,
                                      name: "Pallets",
                                      unitVolume: 1.2,
                                      unitPrice: 100,
                                      shelfLifeDays: 365,
                                      quantity: 50,
                                      totalVolume: 60,
                                      totalPrice: 5_000,
                                      isExpired: false,
                                      type: "Materials")
}

extension AnalysisResult {
    static let sample = AnalysisResult(hasIssues: true,
                                       needsSortingOptimization: true,
                                       needsExpiredRemoval: false,
                                       needsTypeCorrection: true,
                                       problemWarehouseIds: [1])
}

extension AuditLogEntry {
    static func sample(now: Date = .init()) -> AuditLogEntry {
        AuditLogEntry(id: UUID(),
                      timestamp: now,
                      message: "Sample transfer",
                      sourceWarehouseId: 1,
                      targetWarehouseId: 2,
                      operationType: "Transfer",
                      changedItems: [
                        InventoryDelta(id: UUID(), productId: 1, name: "Pallets", quantityChange: -10),
                        InventoryDelta(id: UUID(), productId: 1, name: "Pallets", quantityChange: 10)
                      ])
    }
}
