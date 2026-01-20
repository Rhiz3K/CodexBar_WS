// UsageScheduler.swift
// Periodic usage collection via CodexBarCLI
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation
import Logging

// MARK: - Cost Data Types

/// Cost data for a single provider
struct ProviderCostData: Sendable {
    let provider: String
    let sessionTokens: Int?
    let sessionCostUSD: Double?
    let last30DaysTokens: Int?
    let last30DaysCostUSD: Double?
    let daily: [ProviderCostDaily]
    let modelsUsed: [String]
    let updatedAt: Date
}

struct ProviderCostDaily: Sendable {
    let date: String
    let totalTokens: Int?
    let totalCostUSD: Double?
    let modelBreakdowns: [ProviderCostModelBreakdown]
}

struct ProviderCostModelBreakdown: Sendable {
    let modelName: String
    let costUSD: Double
}

// MARK: - Scheduler Diagnostics

enum SchedulerWarningKind: String, Sendable {
    case usage
    case cost
}

struct SchedulerWarning: Sendable {
    let kind: SchedulerWarningKind
    let providers: String
    let source: String
    let message: String
    let lastSeenAt: Date
}

private struct SchedulerWarningKey: Hashable, Sendable {
    let kind: SchedulerWarningKind
    let providers: String
    let source: String
}

/// Scheduler that periodically fetches usage via CodexBarCLI
actor UsageScheduler {
    private let store: UsageHistoryStore
    private let interval: TimeInterval
    private let logger: Logger
    private let cliPath: String?
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var costData: [String: ProviderCostData] = [:]
    private var warningMap: [SchedulerWarningKey: SchedulerWarning] = [:]

    init(
        store: UsageHistoryStore,
        cliPath: String? = nil,
        providers _: [UsageProvider] = [],
        interval: TimeInterval,
        logger: Logger
    ) {
        self.store = store
        self.interval = interval
        self.logger = logger
        self.cliPath = Self.resolveCLIPath(explicitPath: cliPath)
    }

    /// Start the scheduler
    func start() {
        guard !self.isRunning else {
            self.logger.warning("Scheduler already running")
            return
        }

        guard self.cliPath != nil else {
            self.logger.error("CodexBarCLI not found - scheduler disabled")
            self.logger.info("Install CLI: swift build --product CodexBarCLI")
            return
        }

        self.isRunning = true
        self.logger.info("Starting usage scheduler (interval: \(Int(self.interval))s)")
        self.logger.info("Using CLI: \(self.cliPath!)")

        self.task = Task {
            // Initial fetch
            await self.fetchViaCodexBarCLI()
            await self.fetchCostViaCodexBarCLI()

            // Periodic fetches
            while !Task.isCancelled && self.isRunning {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                    if !Task.isCancelled {
                        await self.fetchViaCodexBarCLI()
                        await self.fetchCostViaCodexBarCLI()
                    }
                } catch {
                    break
                }
            }
        }
    }

    /// Stop the scheduler
    func stop() {
        self.isRunning = false
        self.task?.cancel()
        self.task = nil
        self.logger.info("Scheduler stopped")
    }

    /// Trigger immediate fetch
    func fetchNow() {
        Task {
            await self.fetchViaCodexBarCLI()
            await self.fetchCostViaCodexBarCLI()
        }
    }

    /// Get current cost data for all providers
    func getCostData() -> [String: ProviderCostData] {
        return self.costData
    }

    /// Get cost data for a specific provider
    func getCostData(for provider: String) -> ProviderCostData? {
        return self.costData[provider]
    }

    func getWarnings() -> [SchedulerWarning] {
        Array(self.warningMap.values)
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    // MARK: - CodexBarCLI Integration

    private func fetchViaCodexBarCLI() async {
        guard let cliPath = self.cliPath else {
            self.logger.warning("CodexBarCLI not available")
            return
        }

        self.logger.debug("Starting fetch via CodexBarCLI")

        var allPayloads: [CLIProviderPayload] = []

        // Linux provider/source compatibility (tested):
        // ┌──────────┬─────────────┬───────────┐
        // │ Provider │ cli         │ oauth     │
        // ├──────────┼─────────────┼───────────┤
        // │ codex    │ ✓ codex-cli │ ✓ oauth   │
        // │ claude   │ ✗ timeout   │ ✓ oauth   │
        // │ gemini   │ ✓ api       │ ✗         │
        // │ cursor   │ ✗ macOS     │ ✗         │
        // │ augment  │ ✗ macOS     │ ✗         │
        // │ factory  │ ✗ macOS     │ ✗         │
        // │ others   │ ✗           │ ✗         │
        // └──────────┴─────────────┴───────────┘
        #if os(Linux)
        let fetchConfigs: [(providers: String, source: String)] = [
            ("codex", "cli"), // Uses codex-cli internally
            ("gemini", "cli"), // Uses Gemini API internally
            ("claude", "oauth"), // Requires OAuth token
        ]
        #else
        // On macOS, auto source handles all providers including web-based ones
        let fetchConfigs: [(providers: String, source: String)] = [
            ("all", "auto"),
        ]
        #endif

        for config in fetchConfigs {
            do {
                let result = try await self.runCLI(
                    path: cliPath,
                    arguments: ["--provider", config.providers, "--format", "json", "--source", config.source],
                    timeout: 120
                )

                // Log any errors from CLI (but continue - partial results may be available).
                let stderr = result.stderr ?? ""
                let errorLines = stderr
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.hasPrefix("Error:") }

                if let first = errorLines.first {
                    self.recordWarning(
                        kind: .usage,
                        providers: config.providers,
                        source: config.source,
                        message: first
                    )
                    for line in errorLines {
                        self.logger.debug("CLI [\(config.source)]: \(line)")
                    }
                } else if result.exitCode == 0 {
                    self.clearWarning(kind: .usage, providers: config.providers, source: config.source)
                } else {
                    self.recordWarning(
                        kind: .usage,
                        providers: config.providers,
                        source: config.source,
                        message: "Exit code \(result.exitCode)"
                    )
                }

                if let stdout = result.stdout, !stdout.isEmpty {
                    if let payloads = try? self.parseCLIOutput(stdout) {
                        allPayloads.append(contentsOf: payloads)
                    }
                }
            } catch {
                self.recordWarning(
                    kind: .usage,
                    providers: config.providers,
                    source: config.source,
                    message: error.localizedDescription
                )
                self.logger.warning("Fetch [\(config.source)] failed: \(error.localizedDescription)")
            }
        }

        if allPayloads.isEmpty {
            self.logger.debug("No provider data from any source")
            return
        }

        // Store successful results
        var successCount = 0
        for payload in allPayloads {
            do {
                try await self.store.insertFromCLIPayload(payload)
                self.logger.info("[\(payload.provider)] \(payload.usage.primary?.usedPercent ?? 0)% session, \(payload.usage.secondary?.usedPercent ?? 0)% weekly (\(payload.source))")
                successCount += 1
            } catch {
                self.logger.warning("Failed to store \(payload.provider): \(error.localizedDescription)")
            }
        }

        self.logger.debug("Fetch complete: \(successCount) providers stored")
    }

    // MARK: - Cost Data Fetching

    private func fetchCostViaCodexBarCLI() async {
        guard let cliPath = self.cliPath else {
            return
        }

        self.logger.debug("Fetching cost data via CodexBarCLI")

        // Cost command supports claude and codex
        let providers = ["codex", "claude"]

        for provider in providers {
            do {
                let result = try await self.runCLI(
                    path: cliPath,
                    arguments: ["cost", "--provider", provider, "--format", "json"],
                    timeout: 120
                )

                if result.exitCode != 0 {
                    self.logger.debug("Cost [\(provider)] exit code: \(result.exitCode)")
                    let stderr = result.stderr ?? ""
                    if !stderr.isEmpty {
                        let message = String(stderr.prefix(200))
                        self.recordWarning(kind: .cost, providers: provider, source: "cost", message: message)
                        self.logger.debug("Cost [\(provider)] stderr: \(stderr.prefix(200))")
                    } else {
                        self.recordWarning(kind: .cost, providers: provider, source: "cost", message: "Exit code \(result.exitCode)")
                    }
                    continue
                }

                if let stdout = result.stdout, !stdout.isEmpty {
                    do {
                        let costs = try self.parseCostOutput(stdout)
                        for cost in costs {
                            self.costData[cost.provider] = cost
                            self.logger.debug("[\(cost.provider)] cost: $\(cost.sessionCostUSD ?? 0) today, $\(cost.last30DaysCostUSD ?? 0) 30d, models: \(cost.modelsUsed)")

                            // Persist to SQLite
                            do {
                                try await self.store.insertCost(
                                    provider: cost.provider,
                                    timestamp: cost.updatedAt,
                                    sessionTokens: cost.sessionTokens,
                                    sessionCostUSD: cost.sessionCostUSD,
                                    periodTokens: cost.last30DaysTokens,
                                    periodCostUSD: cost.last30DaysCostUSD,
                                    periodDays: 30,
                                    modelsUsed: cost.modelsUsed
                                )

                                for daily in cost.daily {
                                    try await self.store.upsertCostDaily(
                                        provider: cost.provider,
                                        date: daily.date,
                                        totalTokens: daily.totalTokens,
                                        totalCostUSD: daily.totalCostUSD
                                    )
                                }

                                self.logger.debug("[\(cost.provider)] cost persisted to database")
                            } catch {
                                self.logger.warning("[\(cost.provider)] failed to persist cost: \(error.localizedDescription)")
                            }
                        }

                        self.clearWarning(kind: .cost, providers: provider, source: "cost")
                    } catch {
                        self.recordWarning(kind: .cost, providers: provider, source: "cost", message: "Parse error: \(error.localizedDescription)")
                        self.logger.warning("Cost [\(provider)] parse error: \(error.localizedDescription)")
                    }
                } else {
                    self.logger.debug("Cost [\(provider)] empty output")
                }
            } catch {
                self.recordWarning(kind: .cost, providers: provider, source: "cost", message: error.localizedDescription)
                self.logger.warning("Cost fetch [\(provider)] failed: \(error.localizedDescription)")
            }
        }
    }

    private func parseCostOutput(_ output: String) throws -> [ProviderCostData] {
        guard let data = output.data(using: .utf8) else {
            throw SchedulerError.invalidOutput("Cannot convert cost output to data")
        }

        // The cost command outputs an array of cost payloads
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SchedulerError.invalidOutput("Cannot parse cost JSON")
        }

        var results: [ProviderCostData] = []

        for json in jsonArray {
            guard let provider = json["provider"] as? String else { continue }

            let dailyJSON = json["daily"] as? [[String: Any]] ?? []
            var allModels: Set<String> = []
            var daily: [ProviderCostDaily] = []

            for entry in dailyJSON {
                if let models = entry["modelsUsed"] as? [String] {
                    allModels.formUnion(models)
                }

                let date = entry["date"] as? String ?? ""
                let rawTotalTokens = entry["totalTokens"] as? Int
                let rawTotalCostUSD = entry["totalCost"] as? Double

                // Claude includes cacheRead/cacheCreation tokens which makes totalTokens enormous.
                // For dashboard display we use input+output tokens instead.
                let totalTokens: Int?
                if provider == "claude",
                   let inputTokens = entry["inputTokens"] as? Int,
                   let outputTokens = entry["outputTokens"] as? Int
                {
                    totalTokens = inputTokens + outputTokens
                } else {
                    totalTokens = rawTotalTokens
                }

                var breakdowns: [ProviderCostModelBreakdown] = []
                if let modelBreakdowns = entry["modelBreakdowns"] as? [[String: Any]] {
                    for breakdown in modelBreakdowns {
                        guard let modelName = breakdown["modelName"] as? String,
                              let costUSD = breakdown["cost"] as? Double
                        else {
                            continue
                        }
                        breakdowns.append(ProviderCostModelBreakdown(modelName: modelName, costUSD: costUSD))
                    }
                }

                if !date.isEmpty {
                    daily.append(
                        ProviderCostDaily(
                            date: date,
                            totalTokens: totalTokens,
                            totalCostUSD: rawTotalCostUSD,
                            modelBreakdowns: breakdowns
                        )
                    )
                }
            }

            // Prefer derived totals from the daily list.
            let sortedDaily = daily.sorted { $0.date < $1.date }
            let sessionTokens = sortedDaily.last?.totalTokens
            let sessionCostUSD = sortedDaily.last?.totalCostUSD

            let last30DaysTokens = sortedDaily.reduce(0) { $0 + ($1.totalTokens ?? 0) }
            let last30DaysCostUSD = sortedDaily.reduce(0.0) { $0 + ($1.totalCostUSD ?? 0.0) }

            let cost = ProviderCostData(
                provider: provider,
                sessionTokens: sessionTokens,
                sessionCostUSD: sessionCostUSD,
                last30DaysTokens: sortedDaily.isEmpty ? nil : last30DaysTokens,
                last30DaysCostUSD: sortedDaily.isEmpty ? nil : last30DaysCostUSD,
                daily: daily,
                modelsUsed: Array(allModels).sorted(),
                updatedAt: Date()
            )
            results.append(cost)
        }

        return results
    }

    private func parseCLIOutput(_ output: String) throws -> [CLIProviderPayload] {
        guard let data = output.data(using: .utf8) else {
            throw SchedulerError.invalidOutput("Cannot convert output to data")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try parsing as array first (multiple providers)
        if let payloads = try? decoder.decode([CLIProviderPayload].self, from: data) {
            return payloads
        }

        // Try parsing as single object
        if let payload = try? decoder.decode(CLIProviderPayload.self, from: data) {
            return [payload]
        }

        throw SchedulerError.invalidOutput("Cannot parse CLI JSON output")
    }

    // MARK: - CLI Discovery

    private static func resolveCLIPath(explicitPath: String?) -> String? {
        // 1) Explicit path from CLI argument
        if let explicitPath = explicitPath,
           FileManager.default.isExecutableFile(atPath: explicitPath)
        {
            return explicitPath
        }

        // 2) Environment override
        if let envPath = ProcessInfo.processInfo.environment["CODEXBAR_CLI_PATH"],
           FileManager.default.isExecutableFile(atPath: envPath)
        {
            return envPath
        }

        // 3) PATH lookup
        if let path = try? Self.which("codexbar") {
            return path
        }
        if let path = try? Self.which("CodexBarCLI") {
            return path
        }

        // 4) Fallback: common build output locations
        let candidates = [
            // Built from source (debug)
            FileManager.default.currentDirectoryPath + "/.build/debug/CodexBarCLI",
            FileManager.default.currentDirectoryPath + "/.build/x86_64-unknown-linux-gnu/debug/CodexBarCLI",
            FileManager.default.currentDirectoryPath + "/.build/aarch64-unknown-linux-gnu/debug/CodexBarCLI",
            // Built from source (release)
            FileManager.default.currentDirectoryPath + "/.build/release/CodexBarCLI",
            FileManager.default.currentDirectoryPath + "/.build/x86_64-unknown-linux-gnu/release/CodexBarCLI",
            // System paths
            "/usr/local/bin/codexbar",
            "/opt/homebrew/bin/codexbar",
            // Relative to executable
            Bundle.main.bundlePath + "/../CodexBarCLI",
            Bundle.main.bundlePath + "/CodexBarCLI",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private static func which(_ command: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return nil
        }

        return path
    }

    // MARK: - Process Runner

    private struct CLIResult: Sendable {
        let exitCode: Int32
        let stdout: String?
        let stderr: String?
    }

    private func recordWarning(kind: SchedulerWarningKind, providers: String, source: String, message: String) {
        let key = SchedulerWarningKey(kind: kind, providers: providers, source: source)
        self.warningMap[key] = SchedulerWarning(
            kind: kind,
            providers: providers,
            source: source,
            message: message,
            lastSeenAt: Date()
        )
    }

    private func clearWarning(kind: SchedulerWarningKind, providers: String, source: String) {
        let key = SchedulerWarningKey(kind: kind, providers: providers, source: source)
        self.warningMap[key] = nil
    }

    private func runCLI(path: String, arguments: [String], timeout: TimeInterval) async throws -> CLIResult {
        // `Process.waitUntilExit()` is blocking and would stall the actor, which in turn stalls
        // HTTP handlers awaiting scheduler data (e.g. the dashboard `/` route).
        // Run the process on a detached task so the actor remains responsive.
        try await Self.runCLIProcess(path: path, arguments: arguments, timeout: timeout)
    }

    private nonisolated static func runCLIProcess(
        path: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CLIResult {
        try await Task.detached(priority: .utility) {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                // Filter environment to only include necessary variables (security)
                let fullEnv = ProcessInfo.processInfo.environment
                let allowedKeys: Set<String> = [
                    // Core execution
                    "PATH", "HOME", "SHELL", "USER", "LOGNAME", "LANG", "LC_ALL", "TERM",
                    // Proxy settings
                    "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
                    // Provider API keys
                    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY",
                    "GOOGLE_API_KEY", "GROQ_API_KEY", "MISTRAL_API_KEY",
                ]
                let allowedPrefixes = ["OPENAI_", "ANTHROPIC_", "GEMINI_", "GOOGLE_", "CODEX_", "CLAUDE_"]

                var env: [String: String] = [:]
                for (key, value) in fullEnv {
                    if allowedKeys.contains(key) || allowedPrefixes.contains(where: { key.hasPrefix($0) }) {
                        env[key] = value
                    }
                }
                env["NO_COLOR"] = "1" // Disable ANSI colors
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Timeout handling
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutTask.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = CLIResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8),
                        stderr: String(data: stderrData, encoding: .utf8)
                    )

                    continuation.resume(returning: result)
                } catch {
                    timeoutTask.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }
}

// MARK: - Errors

enum SchedulerError: LocalizedError {
    case cliNotFound
    case invalidOutput(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .cliNotFound: "CodexBarCLI not found"
        case let .invalidOutput(msg): "Invalid CLI output: \(msg)"
        case .timeout: "CLI execution timed out"
        }
    }
}
