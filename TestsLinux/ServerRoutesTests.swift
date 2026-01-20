import CodexBarCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import Testing

@testable import CodexBarServer

@Suite
struct ServerRoutesTests {
    private func createTempStore() throws -> UsageHistoryStore {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_routes_\(UUID().uuidString).sqlite").path
        return try UsageHistoryStore(path: dbPath)
    }

    private func makeApp(store: UsageHistoryStore) -> Application<RouterResponder<BasicRequestContext>> {
        let config = ServerConfig(
            host: "127.0.0.1",
            port: 0,
            databasePath: "test",
            enableScheduler: false,
            schedulerInterval: 0,
            cliPath: nil,
            verbose: false
        )
        var logger = Logger(label: "com.codexbar.server.tests")
        logger.logLevel = .debug

        let state = AppState(store: store, config: config, logger: logger)
        let router = buildRouter(state: state)
        return Application(router: router, logger: logger)
    }

    private func decodeJSON<T: Decodable>(_ response: TestResponse, as _: T.Type) throws -> T {
        let data = Data(response.body.readableBytesView)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    @Test
    func apiRecords_filtersByProvider() async throws {
        struct RecordsResponse: Codable {
            let records: [UsageHistoryRecord]
        }

        let store = try self.createTempStore()
        try await store.insert(UsageHistoryRecord(provider: "codex", timestamp: Date().addingTimeInterval(-60)))
        try await store.insert(UsageHistoryRecord(provider: "claude", timestamp: Date().addingTimeInterval(-30)))
        try await store.insert(UsageHistoryRecord(provider: "claude", timestamp: Date()))

        let app = self.makeApp(store: store)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/api/records?provider=claude&limit=50",
                method: HTTPRequest.Method("GET")!
            )
            #expect(response.status == .ok)
            let payload = try self.decodeJSON(response, as: RecordsResponse.self)
            #expect(payload.records.isEmpty == false)
            #expect(payload.records.allSatisfy { $0.provider == "claude" })
        }
    }

    @Test
    func apiRecords_rejectsUnknownProvider() async throws {
        struct ErrorResponse: Codable {
            let error: String
        }

        let store = try self.createTempStore()
        let app = self.makeApp(store: store)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/api/records?provider=not-a-provider",
                method: HTTPRequest.Method("GET")!
            )
            #expect(response.status == .badRequest)
            let payload = try self.decodeJSON(response, as: ErrorResponse.self)
            #expect(payload.error.isEmpty == false)
        }
    }

    @Test
    func apiRecords_clampsLimit() async throws {
        struct RecordsResponse: Codable {
            let records: [UsageHistoryRecord]
        }

        let store = try self.createTempStore()
        let now = Date()

        for i in 0 ..< 1205 {
            try await store.insert(UsageHistoryRecord(provider: "codex", timestamp: now.addingTimeInterval(Double(i))))
        }

        let app = self.makeApp(store: store)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/api/records?provider=codex&limit=5000",
                method: HTTPRequest.Method("GET")!
            )
            #expect(response.status == .ok)
            let payload = try self.decodeJSON(response, as: RecordsResponse.self)
            #expect(payload.records.count == 1000)
        }
    }
}
