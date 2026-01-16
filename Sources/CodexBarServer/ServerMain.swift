// ServerMain.swift
// CodexBar Web Server - Entry Point
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation
import Hummingbird
import Logging

@main
struct CodexBarServer {
    static func main() async throws {
        // Parse command line arguments
        let config = ServerConfig.fromCommandLine()

        // Setup logging
        var logger = Logger(label: "com.codexbar.server")
        logger.logLevel = config.verbose ? .debug : .info

        logger.info("Starting CodexBar Server v\(Self.version)")
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

    static let version = "0.1.0"
}

// MARK: - Server Configuration

struct ServerConfig: Sendable {
    let host: String
    let port: Int
    let databasePath: String
    let enableScheduler: Bool
    let schedulerInterval: TimeInterval
    let verbose: Bool

    static func fromCommandLine() -> ServerConfig {
        let args = CommandLine.arguments

        func getArg(_ flag: String, default defaultValue: String) -> String {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
                return defaultValue
            }
            return args[index + 1]
        }

        func hasFlag(_ flag: String) -> Bool {
            args.contains(flag)
        }

        return ServerConfig(
            host: getArg("--host", default: "127.0.0.1"),
            port: Int(getArg("--port", default: "8080")) ?? 8080,
            databasePath: getArg("--db", default: UsageHistoryStore.defaultDatabasePath()),
            enableScheduler: !hasFlag("--no-scheduler"),
            schedulerInterval: TimeInterval(getArg("--interval", default: "300")) ?? 300,
            verbose: hasFlag("-v") || hasFlag("--verbose")
        )
    }

    static func printHelp() {
        print("""
            CodexBar Server - Usage Statistics Dashboard

            USAGE:
                codexbar-server [OPTIONS]

            OPTIONS:
                --host <address>      Bind address (default: 127.0.0.1)
                --port <port>         Port number (default: 8080)
                --db <path>           SQLite database path
                --interval <seconds>  Scheduler interval in seconds (default: 300)
                --no-scheduler        Disable automatic usage collection
                -v, --verbose         Enable verbose logging
                --help                Show this help

            NOTES:
                The server uses CodexBarCLI to fetch usage from all available providers.
                Only providers that return valid data will be displayed on the dashboard.

            EXAMPLES:
                codexbar-server
                codexbar-server --port 3000 -v
                codexbar-server --host 0.0.0.0 --port 8080  # Allow remote access
            """)
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
}
