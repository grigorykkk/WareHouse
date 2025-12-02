import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var env: AppEnvironment
    @StateObject private var listVM: WarehouseListViewModel
    @StateObject private var detailVM: WarehouseDetailViewModel
    @StateObject private var analysisVM: AnalysisViewModel
    @StateObject private var logVM: LogViewModel

    @State private var showSettings = false
    @State private var wasOffline = false

    init() {
        let env = AppEnvironment()
        let listVM = WarehouseListViewModel(env: env)
        let detailVM = WarehouseDetailViewModel(env: env)
        let analysisVM = AnalysisViewModel(env: env)
        let logVM = LogViewModel(env: env)

        if ProcessInfo.processInfo.arguments.contains("-uiTestSampleData") {
            let secondary = Warehouse(id: 2,
                                      name: "Secondary",
                                      address: "Тестовый адрес 2",
                                      type: "General",
                                      capacity: 2000,
                                      occupiedVolume: 500,
                                      hasIssues: false,
                                      needsSortingOptimization: false,
                                      needsExpiredRemoval: true,
                                      needsTypeCorrection: false)
            listVM.warehouses = [Warehouse.sample, secondary]
            listVM.selectedWarehouse = Warehouse.sample
            detailVM.seedInventory(for: Warehouse.sample.id, items: [InventoryItem.sample])
            detailVM.seedInventory(for: secondary.id, items: [InventoryItem.sample])
            analysisVM.result = AnalysisResult(hasIssues: true,
                                               needsSortingOptimization: true,
                                               needsExpiredRemoval: true,
                                               needsTypeCorrection: true,
                                               problemWarehouseIds: [Warehouse.sample.id, secondary.id])
            logVM.logs = [AuditLogEntry.sample()]
        }

        _env = StateObject(wrappedValue: env)
        _listVM = StateObject(wrappedValue: listVM)
        _detailVM = StateObject(wrappedValue: detailVM)
        _analysisVM = StateObject(wrappedValue: analysisVM)
        _logVM = StateObject(wrappedValue: logVM)
    }

    var body: some View {
        TabView {
            WarehouseDashboardView(listVM: listVM, detailVM: detailVM, analysisVM: analysisVM)
                .tabItem { Label("Склады", systemImage: "shippingbox") }
                .accessibilityLabel("Сводка складов")

            AnalysisScreen(viewModel: analysisVM, warehouses: listVM.warehouses) { warehouseId in
                listVM.selectedWarehouse = listVM.warehouses.first { $0.id == warehouseId }
            }
            .tabItem { Label("Анализ сети", systemImage: "chart.bar.doc.horizontal") }
            .accessibilityLabel("Анализ сети складов")

            LogsScreen(viewModel: logVM, warehouses: listVM.warehouses)
                .tabItem { Label("Логи", systemImage: "doc.text.magnifyingglass") }
                .accessibilityLabel("Журнал операций")
        }
        .task {
            if listVM.warehouses.isEmpty {
                await listVM.load()
            }
        }
        .onReceive(env.connectivity.$isConnected) { connected in
            if connected {
                if wasOffline {
                    Task {
                        await listVM.load()
                        await analysisVM.runAnalysis()
                        await logVM.load()
                    }
                }
                wasOffline = false
            } else {
                wasOffline = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(configuration: $env.configuration)
                .frame(minWidth: 420, minHeight: 240)
        }
        .toolbar {
            Button {
                showSettings = true
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settingsButton")
            .accessibilityHint("Открыть настройки подключения и токена")
        }
    }
}

struct WarehouseDashboardView: View {
    @ObservedObject var listVM: WarehouseListViewModel
    @ObservedObject var detailVM: WarehouseDetailViewModel
    @ObservedObject var analysisVM: AnalysisViewModel
    @State private var inventorySearch = ""
    @State private var showOnlyProblemWarehouses = false

    private var selectionBinding: Binding<Int?> {
        Binding<Int?>(
            get: { listVM.selectedWarehouse?.id },
            set: { id in
                if let id, let warehouse = listVM.warehouses.first(where: { $0.id == id }) {
                    listVM.selectedWarehouse = warehouse
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Склады")
                        .font(.title2).bold()
                    Spacer()
                    if listVM.isLoading {
                        ProgressView()
                            .accessibilityLabel("Загрузка складов")
                    } else {
                        Button {
                            Task { await listVM.load() }
                        } label: {
                            Label("Обновить", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                        .accessibilityIdentifier("refreshWarehousesButton")
                    }
                }
                if let offline = listVM.offlineLabel {
                    OfflineBadge(text: offline)
                }
                if let error = listVM.errorMessage {
                    ErrorBanner(text: error)
                        .accessibilityIdentifier("warehouseErrorBanner")
                }
                Toggle("Проблемные", isOn: $showOnlyProblemWarehouses)
                    .toggleStyle(.switch)
                    .accessibilityHint("Показывать только склады с проблемами")
                List(selection: selectionBinding) {
                    ForEach(filteredWarehouses()) { warehouse in
                        WarehouseRow(warehouse: warehouse, isProblem: isProblemWarehouse(warehouse))
                            .tag(warehouse.id as Int?)
                            .padding(.vertical, 4)
                    }
                }
                .searchable(text: $listVM.searchText, prompt: "Поиск по названию")
                .listStyle(.inset)
            }
            .padding()
        } detail: {
            if let warehouse = listVM.selectedWarehouse ?? filteredWarehouses().first {
                WarehouseDetailScreen(warehouse: warehouse,
                                      allWarehouses: listVM.warehouses,
                                      detailVM: detailVM,
                                      analysisVM: analysisVM,
                                      inventorySearch: $inventorySearch)
            } else {
                VStack {
                    Text("Выберите склад для просмотра деталей")
                        .foregroundStyle(.secondary)
                    Button("Загрузить данные") {
                        Task { await listVM.load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func filteredWarehouses() -> [Warehouse] {
        let list = listVM.filteredWarehouses
        if showOnlyProblemWarehouses, let result = analysisVM.result, let ids = result.problemWarehouseIds {
            return list.filter { ids.contains($0.id) || ($0.hasIssues ?? false) }
        }
        return list
    }

    private func isProblemWarehouse(_ warehouse: Warehouse) -> Bool {
        if warehouse.hasIssues == true { return true }
        guard let ids = analysisVM.result?.problemWarehouseIds else { return false }
        return ids.contains(warehouse.id)
    }
}

struct WarehouseRow: View {
    let warehouse: Warehouse
    let isProblem: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(warehouse.name)
                    .font(.headline)
                if isProblem {
                    Label("Проблемы", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Склад с проблемами")
                }
                Spacer()
                Text("\(Int(warehouse.fillRate * 100))%")
                    .bold()
                    .accessibilityLabel("Заполнено \(Int(warehouse.fillRate * 100)) процентов")
            }
            ProgressView(value: warehouse.fillRate) {
                Text("Заполнено")
            } currentValueLabel: {
                Text("\(formatVolume(warehouse.occupiedVolume))/\(formatVolume(warehouse.capacity))")
            }
            .accessibilityHint("Емкость склада \(warehouse.capacity)")
            .tint(warehouse.fillRate > 0.85 ? .red : .blue)

            HStack {
                Label("Остаток \(formatVolume(warehouse.remainingVolume))", systemImage: "cube.box")
                if warehouse.needsExpiredRemoval == true {
                    Label("Просрочка", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if warehouse.needsSortingOptimization == true {
                    Label("Оптимизировать", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.purple)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isProblem ? Color.red.opacity(0.08) : Color.gray.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }

    private func formatVolume(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.2f", value)
    }
}

struct WarehouseDetailScreen: View {
    let warehouse: Warehouse
    let allWarehouses: [Warehouse]
    @ObservedObject var detailVM: WarehouseDetailViewModel
    @ObservedObject var analysisVM: AnalysisViewModel
    @Binding var inventorySearch: String
    @State private var inventorySort: InventorySort = .name

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WarehouseCard(warehouse: warehouse, analysis: analysisVM.result)
                InventorySection(items: detailVM.inventory(for: warehouse.id),
                                 searchText: $inventorySearch,
                                 sort: $inventorySort,
                                 isLoading: detailVM.isLoadingInventory,
                                 errorText: detailVM.inventoryError,
                                 offlineLabel: detailVM.inventoryOfflineLabel) {
                    Task { await detailVM.loadInventory(for: warehouse.id) }
                }
                SupplyFormSection(warehouse: warehouse, viewModel: detailVM)
                TransferFormSection(currentWarehouse: warehouse,
                                    warehouses: allWarehouses,
                                    viewModel: detailVM)
            }
            .padding()
        }
        .background(Color(NSColor.textBackgroundColor))
        .navigationTitle(warehouse.name)
        .task(id: warehouse.id) {
            await detailVM.loadInventory(for: warehouse.id)
        }
    }
}

struct WarehouseCard: View {
    let warehouse: Warehouse
    let analysis: AnalysisResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(warehouse.name)
                        .font(.title2).bold()
                    Text(warehouse.address ?? "Адрес не указан")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label("Емкость \(formatVolume(warehouse.capacity))", systemImage: "shippingbox")
                        Label("Свободно \(formatVolume(warehouse.remainingVolume))", systemImage: "square.and.arrow.down")
                    }
                    .font(.callout)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int(warehouse.fillRate * 100))%")
                        .font(.largeTitle).bold()
                    ProgressView(value: warehouse.fillRate)
                        .tint(warehouse.fillRate > 0.85 ? .red : .blue)
                        .frame(width: 160)
                }
            }
            IssueBadges(warehouse: warehouse, analysis: analysis)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Карточка склада с емкостью и статусом")
    }

    private func formatVolume(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.2f", value)
    }
}

struct IssueBadges: View {
    let warehouse: Warehouse
    let analysis: AnalysisResult?

    var body: some View {
        let entry = analysisEntry
        HStack {
            if warehouse.hasIssues == true || entry?.hasIssues == true || (analysis?.problemWarehouseIds?.contains(warehouse.id) == true) {
                Label("Обнаружены проблемы", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
            if warehouse.needsExpiredRemoval == true || entry?.needsExpiredRemoval == true {
                Label("Убрать просрочку", systemImage: "trash.slash")
                    .foregroundStyle(.orange)
            }
            if warehouse.needsSortingOptimization == true || entry?.needsSortingOptimization == true {
                Label("Оптимизировать сортировку", systemImage: "arrow.up.arrow.down.circle")
                    .foregroundStyle(.purple)
            }
            if warehouse.needsTypeCorrection == true || entry?.needsTypeCorrection == true {
                Label("Проверить типы", systemImage: "info.circle")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var analysisEntry: AnalysisEntry? {
        analysis?.entries?.first(where: { $0.warehouseId == warehouse.id })
    }
}

enum InventorySort: String, CaseIterable, Identifiable {
    case name = "Название"
    case quantity = "Количество"
    case price = "Цена"
    case shelfLife = "Срок годности"

    var id: String { rawValue }
}

struct InventorySection: View {
    let items: [InventoryItem]
    @Binding var searchText: String
    @Binding var sort: InventorySort
    let isLoading: Bool
    let errorText: String?
    let offlineLabel: String?
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Инвентарь").font(.title3).bold()
                Spacer()
                Picker("Сортировка", selection: $sort) {
                    ForEach(InventorySort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Сортировка инвентаря")
                Button {
                    reload()
                } label: {
                    Label("Обновить инвентарь", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityIdentifier("refreshInventoryButton")
            }
            if let offlineLabel {
                OfflineBadge(text: offlineLabel)
            }
            if let errorText {
                ErrorBanner(text: errorText)
            }
            TextField("Поиск по названию или поставщику", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inventorySearchField")

            InventoryTable(items: filtered())
                .frame(minHeight: 220)

            if isLoading {
                ProgressView("Загрузка инвентаря...")
                    .padding(.vertical, 6)
                    .accessibilityLabel("Загрузка инвентаря")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }

    private func filtered() -> [InventoryItem] {
        var results = items
        if !searchText.isEmpty {
            results = results.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                "\($0.supplierId)".contains(searchText) ||
                "\($0.productId)".contains(searchText)
            }
        }
        switch sort {
        case .name:
            results.sort { $0.name < $1.name }
        case .quantity:
            results.sort { $0.quantity > $1.quantity }
        case .price:
            results.sort { $0.totalPrice > $1.totalPrice }
        case .shelfLife:
            results.sort { $0.shelfLifeDays < $1.shelfLifeDays }
        }
        return results
    }
}

struct InventoryTable: View {
    let items: [InventoryItem]

    var body: some View {
        Table(items) {
            TableColumn("Товар") { item in
                Text(item.name)
            }
            TableColumn("Количество") { item in
                Text("\(item.quantity)")
            }
            TableColumn("Объем") { item in
                Text(String(format: "%.2f", item.totalVolume))
            }
            TableColumn("Стоимость") { item in
                Text(String(format: "%.2f", item.totalPrice))
            }
            TableColumn("Срок") { item in
                Text("\(item.shelfLifeDays) дн.")
            }
            TableColumn("Статус") { item in
                HStack {
                    if item.isExpired == true {
                        Label("Просрочен", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    if let type = item.type {
                        Text(type)
                            .font(.caption)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)))
                    }
                }
            }
        }
        .accessibilityLabel("Таблица инвентаря")
    }
}

struct SupplyFormSection: View {
    let warehouse: Warehouse
    @ObservedObject var viewModel: WarehouseDetailViewModel
    @State private var items: [SupplyItem] = [SupplyItem()]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Создать поставку").font(.title3).bold()
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView()
                }
            }
            ForEach($items) { $item in
                SupplyItemEditor(item: $item) {
                    items.removeAll { $0.id == item.id }
                }
                .padding(.vertical, 4)
            }
            Button {
                items.append(SupplyItem())
            } label: {
                Label("Добавить позицию", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("addSupplyItemButton")

            if let message = viewModel.submissionMessage {
                Text(message)
                    .foregroundStyle(message.lowercased().contains("ошиб") ? .red : .green)
                    .accessibilityLabel("Результат поставки \(message)")
            }

            Button {
                Task {
                    if await viewModel.submitSupply(for: warehouse.id, items: items) {
                        items = [SupplyItem()]
                    }
                }
            } label: {
                Label("Отправить поставку", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("supplySubmitButton")
            .accessibilityHint("Отправить поставку на сервер")
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }
}

struct SupplyItemEditor: View {
    @Binding var item: SupplyItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Название", text: $item.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("supplyNameField")
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Удалить позицию поставки")
            }
            HStack {
                NumberField(title: "ProductId", value: $item.productId)
                NumberField(title: "SupplierId", value: $item.supplierId)
                NumberField(title: "Количество", value: $item.quantity)
            }
            HStack {
                DecimalField(title: "UnitVolume", value: $item.unitVolume)
                DecimalField(title: "UnitPrice", value: $item.unitPrice)
                NumberField(title: "ShelfLife", value: $item.shelfLifeDays)
            }
        }
    }
}

struct TransferFormSection: View {
    let currentWarehouse: Warehouse
    let warehouses: [Warehouse]
    @ObservedObject var viewModel: WarehouseDetailViewModel

    @State private var targetWarehouse: Warehouse?
    @State private var items: [TransferItem] = [TransferItem()]
    @State private var showWarnings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Перемещение товаров").font(.title3).bold()
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView()
                }
            }
            Picker("Целевой склад", selection: Binding<Warehouse?>(get: { targetWarehouse }, set: { targetWarehouse = $0 })) {
                Text("Выберите склад").tag(Optional<Warehouse>.none)
                ForEach(warehouses.filter { $0.id != currentWarehouse.id }) { warehouse in
                    Text(warehouse.name).tag(Optional(warehouse))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("transferTargetPicker")

            Toggle("Показывать предупреждения", isOn: $showWarnings)
                .toggleStyle(.switch)
                .accessibilityHint("Скрыть уведомления о рисках перемещения")

            if showWarnings {
                TransferWarnings(inventory: viewModel.inventory(for: currentWarehouse.id))
            }

            ForEach($items) { $item in
                TransferItemEditor(item: $item) {
                    items.removeAll { $0.id == item.id }
                }
            }
            Button {
                items.append(TransferItem())
            } label: {
                Label("Добавить позицию", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("addTransferItemButton")

            if let message = viewModel.submissionMessage {
                Text(message)
                    .foregroundStyle(message.lowercased().contains("ошиб") ? .red : .green)
            }

            Button {
                guard let target = targetWarehouse else { return }
                let payload = TransferRequest(sourceWarehouseId: currentWarehouse.id,
                                              destinationWarehouseId: target.id,
                                              items: items.map { $0.asRequestItem })
                Task {
                    _ = await viewModel.submitTransfer(request: payload)
                }
            } label: {
                Label("Отправить перемещение", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(targetWarehouse == nil || viewModel.isSubmitting)
            .accessibilityIdentifier("transferSubmitButton")
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }
}

struct TransferWarnings: View {
    let inventory: [InventoryItem]

    var body: some View {
        let expired = inventory.filter { $0.isExpired == true }
        let unsupported = inventory.filter { $0.type?.isEmpty == true }
        VStack(alignment: .leading, spacing: 4) {
            if !expired.isEmpty {
                Label("Внимание: есть просроченные товары", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Просроченные товары: \(expired.map { $0.name }.joined(separator: ", "))")
            }
            if !unsupported.isEmpty {
                Label("Некоторые товары с неподтвержденным типом", systemImage: "questionmark.diamond")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Неподдерживаемые типы: \(unsupported.map { $0.name }.joined(separator: ", "))")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}

struct TransferItemEditor: View {
    @Binding var item: TransferItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Название", text: $item.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("transferNameField")
                Button(role: .destructive) { onRemove() } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Удалить позицию перемещения")
            }
            HStack {
                NumberField(title: "ProductId", value: $item.productId)
                NumberField(title: "Количество", value: $item.quantity)
            }
        }
    }
}

struct AnalysisScreen: View {
    @ObservedObject var viewModel: AnalysisViewModel
    let warehouses: [Warehouse]
    let selectWarehouse: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Анализ сети").font(.title2).bold()
                Spacer()
                Button {
                    Task { await viewModel.runAnalysis() }
                } label: {
                    Label("Запустить анализ", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runAnalysisButton")
                if viewModel.isLoading {
                    ProgressView().accessibilityLabel("Идет анализ")
                }
            }
            if let offline = viewModel.offlineLabel {
                OfflineBadge(text: offline)
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(text: error)
            }
            if let result = viewModel.result {
                AnalysisResultView(result: result, warehouses: warehouses, selectWarehouse: selectWarehouse)
            } else {
                Text("Нет результатов анализа. Запустите проверку.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .task {
            if viewModel.result == nil {
                await viewModel.runAnalysis()
            }
        }
    }
}

struct AnalysisResultView: View {
    let result: AnalysisResult
    let warehouses: [Warehouse]
    let selectWarehouse: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusRow(title: "Есть проблемы", isActive: result.hasIssues, color: .red)
            StatusRow(title: "Нужно оптимизировать сортировку", isActive: result.needsSortingOptimization, color: .purple)
            StatusRow(title: "Нужно убрать просрочку", isActive: result.needsExpiredRemoval, color: .orange)
            StatusRow(title: "Нужно проверить типы", isActive: result.needsTypeCorrection, color: .yellow)
            if let ids = result.problemWarehouseIds, !ids.isEmpty {
                Text("Проблемные склады").font(.headline)
                ForEach(ids, id: \.self) { id in
                    if let warehouse = warehouses.first(where: { $0.id == id }) {
                        Button {
                            selectWarehouse(id)
                        } label: {
                            HStack {
                                Text(warehouse.name)
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Открыть \(warehouse.name)")
                    } else {
                        Text("Склад \(id)")
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }
}

struct StatusRow: View {
    let title: String
    let isActive: Bool
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(isActive ? color : .gray.opacity(0.4))
                .frame(width: 12, height: 12)
            Text(title)
                .foregroundStyle(isActive ? .primary : .secondary)
            Spacer()
            Text(isActive ? "Да" : "Нет")
                .foregroundStyle(isActive ? color : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(isActive ? "Да" : "Нет")")
    }
}

struct LogsScreen: View {
    @ObservedObject var viewModel: LogViewModel
    let warehouses: [Warehouse]
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Журнал операций").font(.title2).bold()
                Spacer()
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("refreshLogsButton")
                if viewModel.isLoading {
                    ProgressView().accessibilityLabel("Загрузка логов")
                }
            }
            if let offline = viewModel.offlineLabel {
                OfflineBadge(text: offline)
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(text: error)
            }
            filterControls
            List(viewModel.filteredLogs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.operationType).bold()
                        Spacer()
                        Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Text(log.message)
                        .font(.body)
                    HStack {
                        if let source = log.sourceWarehouseId {
                            Text("Из: \(warehouseName(for: source))")
                        }
                        if let target = log.targetWarehouseId {
                            Text("В: \(warehouseName(for: target))")
                        }
                    }
                    .font(.callout)
                    if !log.changedItems.isEmpty {
                        let itemsSummary = log.changedItems
                            .map { "\($0.name) (\($0.quantityChange))" }
                            .joined(separator: ", ")
                        Text("Позиции: \(itemsSummary)")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 6)
            }
            .accessibilityLabel("Список логов")
        }
        .padding()
        .task {
            if viewModel.logs.isEmpty {
                await viewModel.load()
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Поиск по операции или товару", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("logSearchField")
                Picker("Склад", selection: Binding<Int?>(get: { viewModel.selectedWarehouseId }, set: { viewModel.selectedWarehouseId = $0 })) {
                    Text("Все").tag(Optional<Int>.none)
                    ForEach(warehouses) { warehouse in
                        Text(warehouse.name).tag(Optional(warehouse.id))
                    }
                }
                .pickerStyle(.menu)
                Picker("Тип операции", selection: Binding<String?>(get: { viewModel.selectedOperation }, set: { viewModel.selectedOperation = $0 })) {
                    Text("Все").tag(Optional<String>.none)
                    Text("Supply").tag(Optional("Supply"))
                    Text("Transfer").tag(Optional("Transfer"))
                    Text("Log").tag(Optional("Log"))
                }
                .pickerStyle(.menu)
            }
            HStack {
                DatePicker("C", selection: $dateFrom, displayedComponents: .date)
                DatePicker("По", selection: $dateTo, displayedComponents: .date)
                Button("Применить даты") {
                    viewModel.dateRange = dateFrom...dateTo
                }
                Button("Сбросить даты") {
                    viewModel.dateRange = nil
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
    }

    private func warehouseName(for id: Int) -> String {
        warehouses.first(where: { $0.id == id })?.name ?? "Склад \(id)"
    }
}

struct OfflineBadge: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
            .accessibilityLabel("Офлайн режим: \(text)")
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
        .foregroundStyle(.red)
        .accessibilityLabel("Ошибка: \(text)")
    }
}

struct SettingsView: View {
    @Binding var configuration: AppConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки соединения").font(.title2).bold()
            TextField("Адрес бэкенда", text: Binding(
                get: { configuration.baseURL.absoluteString },
                set: { newValue in
                    if let url = URL(string: newValue) {
                        configuration.baseURL = url
                    }
                }))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("backendURLField")
            SecureField("Токен (опционально)", text: Binding(
                get: { configuration.token ?? "" },
                set: { configuration.token = $0.isEmpty ? nil : $0 }))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("authTokenField")
            Spacer()
        }
        .padding()
    }
}

struct NumberField<T: BinaryInteger>: View {
    let title: String
    @Binding var value: T

    var body: some View {
        TextField(title, value: $value, formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 120)
            .accessibilityLabel(title)
    }
}

struct DecimalField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 120)
            .accessibilityLabel(title)
    }
}

#Preview {
    ContentView()
}
