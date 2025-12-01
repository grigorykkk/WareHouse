import Foundation
import Combine
import SwiftUI

@MainActor
final class WarehouseListViewModel: ObservableObject {
    @Published var warehouses: [Warehouse] = []
    @Published var searchText: String = ""
    @Published var sortByFillRate: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var offlineLabel: String?
    @Published var lastUpdated: Date?
    @Published var selectedWarehouse: Warehouse?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var filteredWarehouses: [Warehouse] {
        let list = warehouses.filter { warehouse in
            searchText.isEmpty || warehouse.name.localizedCaseInsensitiveContains(searchText)
        }
        if sortByFillRate {
            return list.sorted { $0.fillRate > $1.fillRate }
        } else {
            return list.sorted { $0.name < $1.name }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await env.api.fetchWarehouses()
            warehouses = data
            if selectedWarehouse == nil {
                selectedWarehouse = data.first
            }
            lastUpdated = Date()
            offlineLabel = nil
            env.cache.save(CachedEntry(timestamp: Date(), value: data), for: .warehouses)
        } catch {
            env.logger.log("Warehouses load failed: \(error.localizedDescription)")
            handleLoadFallback(error: error)
        }
        isLoading = false
    }

    private func handleLoadFallback(error: Error) {
        if let cached: CachedEntry<[Warehouse]> = env.cache.load(for: .warehouses) {
            warehouses = cached.value
            if selectedWarehouse == nil {
                selectedWarehouse = cached.value.first
            }
            lastUpdated = cached.timestamp
            offlineLabel = "Офлайн данные от \(formatted(date: cached.timestamp))"
            errorMessage = error.localizedDescription
        } else {
            errorMessage = "Не удалось загрузить склады: \(error.localizedDescription)"
        }
    }

    func updateWarehouse(_ warehouse: Warehouse) {
        if let index = warehouses.firstIndex(where: { $0.id == warehouse.id }) {
            warehouses[index] = warehouse
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor
final class WarehouseDetailViewModel: ObservableObject {
    @Published private(set) var inventories: [Int: [InventoryItem]] = [:]
    @Published var isLoadingInventory: Bool = false
    @Published var inventoryError: String?
    @Published var inventoryOfflineLabel: String?
    @Published var isSubmitting: Bool = false
    @Published var submissionMessage: String?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func inventory(for warehouseId: Int) -> [InventoryItem] {
        inventories[warehouseId] ?? []
    }

    func loadInventory(for warehouseId: Int) async {
        isLoadingInventory = true
        inventoryError = nil
        do {
            let items = try await env.api.fetchInventory(for: warehouseId)
            inventories[warehouseId] = items
            inventoryOfflineLabel = nil
            env.cache.save(CachedEntry(timestamp: Date(), value: items), for: .inventory(warehouseId))
        } catch {
            env.logger.log("Inventory load failed: \(error.localizedDescription)")
            if let cached: CachedEntry<[InventoryItem]> = env.cache.load(for: .inventory(warehouseId)) {
                inventories[warehouseId] = cached.value
                inventoryOfflineLabel = "Офлайн данные от \(format(date: cached.timestamp))"
            }
            inventoryError = error.localizedDescription
        }
        isLoadingInventory = false
    }

    func seedInventory(for warehouseId: Int, items: [InventoryItem]) {
        inventories[warehouseId] = items
    }

    func submitSupply(for warehouseId: Int, items: [SupplyItem]) async -> Bool {
        let validation = validateSupply(items: items)
        guard validation.isEmpty else {
            submissionMessage = validation.joined(separator: "\n")
            return false
        }

        isSubmitting = true
        submissionMessage = nil
        defer { isSubmitting = false }
        let payload = SupplyRequest(warehouseId: warehouseId, items: items.map { $0.asRequestItem })
        do {
            let response = try await env.api.createSupply(payload)
            inventories[warehouseId] = response.updatedInventory
            env.cache.save(CachedEntry(timestamp: Date(), value: response.updatedInventory), for: .inventory(warehouseId))
            submissionMessage = response.message ?? "Поставка создана."
            return true
        } catch {
            env.logger.log("Supply failed: \(error.localizedDescription)")
            submissionMessage = error.localizedDescription
            return false
        }
    }

    func submitTransfer(request: TransferRequest) async -> TransferResponse? {
        let validation = validateTransfer(request: request)
        guard validation.isEmpty else {
            submissionMessage = validation.joined(separator: "\n")
            return nil
        }

        isSubmitting = true
        submissionMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await env.api.createTransfer(request)
            inventories[request.fromWarehouseId] = response.sourceInventory
            inventories[request.toWarehouseId] = response.targetInventory
            env.cache.save(CachedEntry(timestamp: Date(), value: response.sourceInventory), for: .inventory(request.fromWarehouseId))
            env.cache.save(CachedEntry(timestamp: Date(), value: response.targetInventory), for: .inventory(request.toWarehouseId))
            submissionMessage = response.message ?? "Перемещение завершено."
            return response
        } catch {
            env.logger.log("Transfer failed: \(error.localizedDescription)")
            submissionMessage = error.localizedDescription
            return nil
        }
    }

    private func validateSupply(items: [SupplyItem]) -> [String] {
        var problems: [String] = []
        if items.isEmpty {
            problems.append("Добавьте хотя бы одну позицию.")
        }
        for item in items {
            if item.name.isEmpty { problems.append("Укажите название товара.") }
            if item.productId <= 0 { problems.append("ProductId должен быть положительным.") }
            if item.supplierId <= 0 { problems.append("SupplierId должен быть положительным.") }
            if item.unitVolume <= 0 { problems.append("UnitVolume должен быть больше нуля.") }
            if item.unitPrice < 0 { problems.append("UnitPrice не может быть отрицательным.") }
            if item.quantity <= 0 { problems.append("Количество должно быть больше нуля.") }
        }
        return problems
    }

    private func validateTransfer(request: TransferRequest) -> [String] {
        var problems: [String] = []
        if request.fromWarehouseId == request.toWarehouseId {
            problems.append("Исходный и целевой склады должны различаться.")
        }
        if request.items.isEmpty {
            problems.append("Добавьте позиции для перемещения.")
        }
        for item in request.items where item.quantity <= 0 {
            problems.append("Количество для перемещения должно быть больше нуля.")
        }
        return problems
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var result: AnalysisResult?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var offlineLabel: String?
    @Published var lastUpdated: Date?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func runAnalysis() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await env.api.runAnalysis()
            result = response
            lastUpdated = Date()
            offlineLabel = nil
            env.cache.save(CachedEntry(timestamp: Date(), value: response), for: .analysis)
        } catch {
            env.logger.log("Analysis failed: \(error.localizedDescription)")
            if let cached: CachedEntry<AnalysisResult> = env.cache.load(for: .analysis) {
                result = cached.value
                lastUpdated = cached.timestamp
                offlineLabel = "Офлайн данные от \(format(date: cached.timestamp))"
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor
final class LogViewModel: ObservableObject {
    @Published var logs: [AuditLogEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var offlineLabel: String?
    @Published var lastUpdated: Date?
    @Published var searchText: String = ""
    @Published var selectedWarehouseId: Int?
    @Published var selectedOperation: String?
    @Published var dateRange: ClosedRange<Date>?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var filteredLogs: [AuditLogEntry] {
        logs.filter { entry in
            var matches = true
            if let warehouseId = selectedWarehouseId {
                matches = matches && (entry.sourceWarehouseId == warehouseId || entry.targetWarehouseId == warehouseId)
            }
            if let operation = selectedOperation {
                matches = matches && entry.operationType.localizedCaseInsensitiveContains(operation)
            }
            if let range = dateRange {
                matches = matches && range.contains(entry.timestamp)
            }
            if !searchText.isEmpty {
                let itemsText = entry.changedItems.map { $0.name }.joined(separator: ", ")
                matches = matches && (itemsText.localizedCaseInsensitiveContains(searchText) || entry.operationType.localizedCaseInsensitiveContains(searchText))
            }
            return matches
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let query = LogQuery(warehouseId: selectedWarehouseId, operationType: selectedOperation, dateRange: dateRange)
        do {
            let result = try await env.api.fetchLogs(query: query)
            logs = result
            lastUpdated = Date()
            offlineLabel = nil
            env.cache.save(CachedEntry(timestamp: Date(), value: result), for: .logs)
        } catch {
            env.logger.log("Logs load failed: \(error.localizedDescription)")
            if let cached: CachedEntry<[AuditLogEntry]> = env.cache.load(for: .logs) {
                logs = cached.value
                lastUpdated = cached.timestamp
                offlineLabel = "Офлайн данные от \(format(date: cached.timestamp))"
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
