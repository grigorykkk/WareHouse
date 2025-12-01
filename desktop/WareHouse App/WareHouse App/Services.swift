import Foundation
import Combine
import Network

final class CacheStore {
    private let queue = DispatchQueue(label: "WareHouseApp.Cache", qos: .background)
    private let fileManager = FileManager.default
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("WareHouseAppCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        directory = dir

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save<T: Codable>(_ entry: CachedEntry<T>, for key: CacheKey) {
        let url = directory.appendingPathComponent("\(key.rawValue).json")
        let data: Data
        do {
            data = try encoder.encode(entry)
        } catch {
            print("Cache write error: \(error)")
            return
        }
        queue.async { [data, url] in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("Cache write error: \(error)")
            }
        }
    }

    func load<T: Codable>(for key: CacheKey, as type: T.Type = T.self) -> CachedEntry<T>? {
        let url = directory.appendingPathComponent("\(key.rawValue).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedEntry<T>.self, from: data)
    }
}

final class AppLogger {
    private let queue = DispatchQueue(label: "WareHouseApp.Logger", qos: .background)
    private let logURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        logURL = base.appendingPathComponent("WareHouseApp.log")
        ensureFileExists()
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async { [line, logURL] in
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
        }
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }
}

final class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()
    @Published private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "WareHouseApp.Connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
