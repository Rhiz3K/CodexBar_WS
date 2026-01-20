// ServerMain.swift
// CodexBar Web Server - Entry Point
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation
import Hummingbird
import Logging
import ArgumentParser

@main
struct CodexBarServer: AsyncParsableCommand {
    static let version = "0.1.0"

    static let configuration = CommandConfiguration(
        commandName: "codexbar-server",
        abstract: "CodexBar Server - Usage Statistics Dashboard"
    )

    @Option(name: .long, help: "Bind address.")
    var host: String = ProcessInfo.processInfo.environment["CODEXBAR_HOST"] ?? "127.0.0.1"

    @Option(name: .long, help: "Port number.")
    var port: Int = Int(ProcessInfo.processInfo.environment["CODEXBAR_PORT"] ?? "") ?? 8080

    @Option(name: .long, help: "SQLite database path.")
    var db: String = ProcessInfo.processInfo.environment["CODEXBAR_DB_PATH"]
        ?? UsageHistoryStore.defaultDatabasePath()

    @Option(name: .long, help: "Scheduler interval in seconds.")
    var interval: Int = Int(ProcessInfo.processInfo.environment["CODEXBAR_INTERVAL"] ?? "") ?? 300

    @Flag(name: .long, help: "Disable automatic usage collection.")
    var noScheduler: Bool = false

    @Option(name: .long, help: "Explicit path to CodexBarCLI executable.")
    var cliPath: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging.")
    var verbose: Bool = false

    func run() async throws {
        let config = ServerConfig(
            host: self.host,
            port: self.port,
            databasePath: self.db,
            enableScheduler: !self.noScheduler,
            schedulerInterval: TimeInterval(self.interval),
            cliPath: self.cliPath,
            verbose: self.verbose
        )

        var logger = Logger(label: "com.codexbar.server")
        logger.logLevel = config.verbose ? .debug : .info

        logger.info("Starting CodexBar Server v\(Self.version)")
        logger.info("Database: \(config.databasePath)")
        logger.info("Binding to \(config.host):\(config.port)")

        let store = try UsageHistoryStore(path: config.databasePath)
        let recordCount = (try? await store.recordCount()) ?? 0

        do {
            try await store.backfillUsageHourly()
        } catch {
            logger.warning("Hourly usage backfill failed: \(error.localizedDescription)")
        }
        logger.info("Database initialized with \(recordCount) records")

        let appState = AppState(store: store, config: config, logger: logger)

        if config.enableScheduler {
            await appState.startScheduler()
        }

        let router = buildRouter(state: appState)

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(config.host, port: config.port),
                serverName: "CodexBar Server"
            ),
            logger: logger
        )

        logger.info("Server ready at http://\(config.host):\(config.port)")
        try await app.runService()
    }
}

// MARK: - Server Configuration

struct ServerConfig: Sendable {
    let host: String
    let port: Int
    let databasePath: String
    let enableScheduler: Bool
    let schedulerInterval: TimeInterval
    let cliPath: String?
    let verbose: Bool
}

// MARK: - Application State

final class AppState: Sendable {
    let store: UsageHistoryStore
    let config: ServerConfig
    let logger: Logger
    let predictionEngine: UsagePredictionEngine
    private let scheduler: UsageScheduler

    init(store: UsageHistoryStore, config: ServerConfig, logger: Logger) {
        self.store = store
        self.config = config
        self.logger = logger
        self.predictionEngine = UsagePredictionEngine()
        self.scheduler = UsageScheduler(
            store: store,
            cliPath: config.cliPath,
            interval: config.schedulerInterval,
            logger: logger
        )
    }

    func startScheduler() async {
        await self.scheduler.start()
    }

    func stopScheduler() async {
        await self.scheduler.stop()
    }

    func triggerFetch() async {
        await self.scheduler.fetchNow()
    }

    func getCostData() async -> [String: ProviderCostData] {
        await self.scheduler.getCostData()
    }

    func getCostData(for provider: String) async -> ProviderCostData? {
        await self.scheduler.getCostData(for: provider)
    }

    func getWarnings() async -> [SchedulerWarning] {
        await self.scheduler.getWarnings()
    }
}
