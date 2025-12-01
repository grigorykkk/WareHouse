import Foundation
import Combine

struct AppConfiguration: Codable, Equatable {
    var baseURL: URL
    var token: String?

    static var `default`: AppConfiguration {
        AppConfiguration(baseURL: URL(string: "https://localhost:5030")!, token: nil)
    }

    static private let storageKey = "WareHouseApp.Configuration"

    static func load() -> AppConfiguration {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: AppConfiguration.storageKey)
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var configuration: AppConfiguration {
        didSet {
            configuration.persist()
            api.configuration = configuration
        }
    }

    let api: WarehouseAPI
    let cache: CacheStore
    let logger: AppLogger
    let connectivity: ConnectivityMonitor

    init(configuration: AppConfiguration? = nil) {
        let resolvedConfig = configuration ?? AppConfiguration.load()
        let cache = CacheStore()
        let logger = AppLogger()
        let connectivity = ConnectivityMonitor.shared
        self.configuration = resolvedConfig
        self.cache = cache
        self.logger = logger
        self.connectivity = connectivity
        self.api = WarehouseAPI(configuration: resolvedConfig, logger: logger)
    }

    static var preview: AppEnvironment {
        AppEnvironment(configuration: .default)
    }
}
