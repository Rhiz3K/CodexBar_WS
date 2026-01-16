// ServerMain.swift
// CodexBar Web Server - Entry Point
// Cross-platform: macOS and Linux

import ArgumentParser
import CodexBarCore
import Foundation
import Hummingbird
import Logging

@main
struct CodexBarServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codexbar-server",
        abstract: "CodexBar Server - Usage Statistics Dashboard",
        discussion: """
            A web server that displays usage statistics for AI providers (Codex, Claude, Gemini).
            The server uses CodexBarCLI to fetch usage data and displays it on a dashboard.
            """,
        version: "0.1.0"
    )

    @Option(name: .long, help: "Bind address")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Port number")
    var port: Int = 8080

    @Option(name: .long, help: "SQLite database path")
    var db: String?

    @Option(name: .long, help: "Scheduler interval in seconds")
    var interval: Int = 300

    @Option(name: .long, help: "Path to CodexBarCLI executable")
    var cliPath: String?

    @Flag(name: .long, help: "Disable automatic usage collection")
    var noScheduler: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false

    func run() async throws {
        // Build config from parsed arguments
        let config = ServerConfig(
            host: self.host,
            port: self.port,
            databasePath: self.db ?? UsageHistoryStore.defaultDatabasePath(),
            enableScheduler: !self.noScheduler,
            schedulerInterval: TimeInterval(self.interval),
            verbose: self.verbose,
            cliPath: self.cliPath
        )

        // Setup logging
        var logger = Logger(label: "com.codexbar.server")
        logger.logLevel = config.verbose ? .debug : .info

        logger.info("Starting CodexBar Server v\(Self.configuration.version)")
        logger.info("Database: \(config.databasePath)")
        logger.info("Binding to \(config.host):\(config.port)")

        // Initialize storage
        let store = try UsageHistoryStore(path: config.databasePath)
        let recordCount = (try? store.recordCount()) ?? 0
        logger.info("Database initialized with \(recordCount) records")

        // Create app state
        let appState = AppState(
            store: store,
            config: config,
            logger: logger
        )

        // Start usage scheduler if enabled
        if config.enableScheduler {
            await appState.startScheduler()
        }

        // Build router
        let router = buildRouter(state: appState)

        // Create and run application
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
    let verbose: Bool
    let cliPath: String?

    init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        databasePath: String? = nil,
        enableScheduler: Bool = true,
        schedulerInterval: TimeInterval = 300,
        verbose: Bool = false,
        cliPath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.databasePath = databasePath ?? UsageHistoryStore.defaultDatabasePath()
        self.enableScheduler = enableScheduler
        self.schedulerInterval = schedulerInterval
        self.verbose = verbose
        self.cliPath = cliPath
    }
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
            interval: config.schedulerInterval,
            logger: logger,
            cliPath: config.cliPath
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
}
