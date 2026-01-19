import CodexBarCore
import Commander
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

// MARK: - Server Command

extension CodexBarCLI {
    static func runServerCommand(argv: [String]) -> Never {
        let version = Self.cliVersionString()
        var argv = argv

        if argv.first == "-V" || argv.first == "--version" {
            Self.printVersion()
        }

        if argv.isEmpty || argv.first == "-h" || argv.first == "--help" {
            print(Self.serverHelp(version: version))
            Self.exit(code: .success)
        }

        let subcommand = argv.removeFirst()
        switch subcommand {
        case "run":
            Self.execCodexBarServer(argv: argv)

        case "install":
            Self.installCodexBarServer(argv: argv)

        case "uninstall":
            Self.uninstallCodexBarServer(argv: argv)

        default:
            Self.exit(code: .failure, message: "Error: Unknown server subcommand '\(subcommand)'.")
        }
    }

    // MARK: - run

    private static func execCodexBarServer(argv: [String]) -> Never {
        guard let serverPath = Self.resolveServerExecutable() else {
            Self.exit(
                code: .failure,
                message: "Error: codexbar-server not found. Install via: brew install steipete/tap/codexbar")
        }

        Self.execBinary(path: serverPath, arguments: argv)
    }

    // MARK: - install

    // MARK: - uninstall

    private static func uninstallCodexBarServer(argv: [String]) -> Never {
        #if os(Linux)
        let version = Self.cliVersionString()
        let argv = argv

        if argv.first == "-h" || argv.first == "--help" {
            print(Self.serverUninstallHelp(version: version))
            Self.exit(code: .success)
        }

        let unitURL = Self.systemdUserUnitURL(serviceName: "codexbar-server")

        do {
            // Stop/disable if present. These can fail if the unit isn't loaded yet; treat failures as non-fatal.
            try? Self.runSystemctlUser(["disable", "--now", "codexbar-server"])

            if FileManager.default.fileExists(atPath: unitURL.path) {
                try FileManager.default.removeItem(at: unitURL)
            }

            try? Self.runSystemctlUser(["daemon-reload"])
        } catch {
            Self.exit(code: .failure, message: "Error: Failed to uninstall service: \(error.localizedDescription)")
        }

        print("Uninstalled systemd user service: codexbar-server")
        print("Removed: \(unitURL.path)")
        Self.exit(code: .success)
        #else
        Self.exit(code: .failure, message: "Error: codexbar server uninstall is only supported on Linux.")
        #endif
    }

    // MARK: - install

    private static func installCodexBarServer(argv: [String]) -> Never {
        #if os(Linux)
        let version = Self.cliVersionString()
        let argv = argv

        if argv.first == "-h" || argv.first == "--help" {
            print(Self.serverInstallHelp(version: version))
            Self.exit(code: .success)
        }

        var force = false
        var serverArgs: [String] = []
        for arg in argv {
            if arg == "--force" {
                force = true
                continue
            }
            serverArgs.append(arg)
        }

        guard let serverPath = Self.resolveServerExecutable() else {
            Self.exit(
                code: .failure,
                message: "Error: codexbar-server not found. Install via: brew install steipete/tap/codexbar")
        }

        let cliPath = Self.resolveCurrentExecutablePath()
            ?? TTYCommandRunner.which("codexbar")
            ?? TTYCommandRunner.which("CodexBarCLI")

        guard let cliPath else {
            Self.exit(code: .failure, message: "Error: Unable to locate codexbar executable for scheduler.")
        }

        let unitURL = Self.systemdUserUnitURL(serviceName: "codexbar-server")

        if FileManager.default.fileExists(atPath: unitURL.path), !force {
            Self.exit(
                code: .failure,
                message: "Error: Unit already exists at \(unitURL.path). Re-run with --force to overwrite.")
        }

        do {
            try FileManager.default.createDirectory(
                at: unitURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        } catch {
            Self.exit(code: .failure, message: "Error: Failed to create systemd user dir: \(error.localizedDescription)")
        }

        let envPATH = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let unitText = Self.systemdUserUnit(
            serverPath: serverPath,
            serverArgs: serverArgs,
            cliPath: cliPath,
            pathEnv: envPATH,
            description: "CodexBar Server")

        do {
            try unitText.write(to: unitURL, atomically: true, encoding: .utf8)
        } catch {
            Self.exit(code: .failure, message: "Error: Failed to write unit file: \(error.localizedDescription)")
        }

        do {
            try Self.runSystemctlUser(["daemon-reload"])
            try Self.runSystemctlUser(["enable", "--now", "codexbar-server"])
        } catch {
            Self.exit(code: .failure, message: "Error: systemctl failed: \(error.localizedDescription)")
        }

        let endpoint = Self.parseServerEndpoint(from: serverArgs)
        print("Installed and started systemd user service: codexbar-server")
        print("Dashboard: \(endpoint.dashboardURL)")
        print("Next:")
        print("  systemctl --user status codexbar-server")
        print("  journalctl --user -u codexbar-server -f")

        Self.exit(code: .success)
        #else
        Self.exit(code: .failure, message: "Error: codexbar server install is only supported on Linux.")
        #endif
    }

    // MARK: - Help

    static func serverHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar server run [server options...]
          codexbar server install [--force] [server options...]
          codexbar server uninstall

        Description:
          Manage the CodexBar web dashboard server (CodexBarServer).
          - run: start the server in the foreground
          - install: install + enable a systemd user service (Linux)
          - uninstall: stop/disable the user service and remove the unit file

        Notes:
          Server options are forwarded to `codexbar-server` (e.g. --host, --port, --db, --interval, --no-scheduler, --cli-path, -v).
          `uninstall` is safe to run multiple times and only removes the systemd user unit file (it does not delete your DB/history).
          Tip: `codexbar server run --help` shows the full server option list.

        Examples:
          codexbar server run -v
          codexbar server run --port 9000
          codexbar server install --port 9000 --interval 300 -v
          codexbar server uninstall
          systemctl --user status codexbar-server
          journalctl --user -u codexbar-server -f
        """
    }

    static func serverInstallHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar server install [--force] [server options...]

        Description:
          Installs a systemd user service (starts after login).
          Writes: ~/.config/systemd/user/codexbar-server.service
          Enables + starts it via systemctl --user.

        Options:
          --force   Overwrite existing unit file

        Examples:
          codexbar server install --port 9000 -v
          codexbar server install --db ~/.codexbar/usage_history.sqlite --interval 60 --no-scheduler

        After install:
          systemctl --user status codexbar-server
          journalctl --user -u codexbar-server -f
        """
    }

    static func serverUninstallHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar server uninstall

        Description:
          Stops + disables the systemd user service (if present) and removes:
            ~/.config/systemd/user/codexbar-server.service

          This does not delete your database/history (e.g. ~/.codexbar/usage_history.sqlite).
          Safe to run multiple times.

        Examples:
          codexbar server uninstall

        After uninstall:
          systemctl --user status codexbar-server
        """
    }

    // MARK: - Internals (shared + tests)

    static func cliVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static func resolveCurrentExecutablePath() -> String? {
        guard let argv0 = CommandLine.arguments.first, !argv0.isEmpty else { return nil }

        let url: URL
        if argv0.hasPrefix("/") {
            url = URL(fileURLWithPath: argv0)
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(argv0)
        }

        let resolved = url.resolvingSymlinksInPath().path
        return FileManager.default.isExecutableFile(atPath: resolved) ? resolved : nil
    }

    static func resolveServerExecutable() -> String? {
        // 1) PATH lookup
        if let located = TTYCommandRunner.which("codexbar-server") {
            return located
        }
        if let located = TTYCommandRunner.which("CodexBarServer") {
            return located
        }

        // 2) Sibling to current executable (release tarball use-case)
        if let current = Self.resolveCurrentExecutablePath() {
            let dir = URL(fileURLWithPath: current).deletingLastPathComponent()
            let siblingCandidates = [
                dir.appendingPathComponent("codexbar-server").path,
                dir.appendingPathComponent("CodexBarServer").path,
            ]
            for path in siblingCandidates where FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3) Fallback: common build output locations
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            cwd + "/.build/debug/CodexBarServer",
            cwd + "/.build/x86_64-unknown-linux-gnu/debug/CodexBarServer",
            cwd + "/.build/aarch64-unknown-linux-gnu/debug/CodexBarServer",
            cwd + "/.build/release/CodexBarServer",
            cwd + "/.build/x86_64-unknown-linux-gnu/release/CodexBarServer",
            "/usr/local/bin/codexbar-server",
            "/opt/homebrew/bin/codexbar-server",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private static func execBinary(path: String, arguments: [String]) -> Never {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let argv = [resolvedPath] + arguments

        var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cStrings.append(nil)

        let result = cStrings.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return Int32(-1)
            }
            return execv(resolvedPath, baseAddress)
        }

        let err = errno
        for ptr in cStrings where ptr != nil {
            free(ptr)
        }

        if result == -1 {
            let msg = String(cString: strerror(err))
            Self.exit(code: .failure, message: "Error: Failed to exec \(resolvedPath): \(msg)")
        }

        Self.exit(code: .failure, message: "Error: Unexpected exec failure")
    }

    #if os(Linux)
    struct ServerEndpoint: Sendable {
        let host: String
        let port: Int

        var dashboardURL: String {
            let isIPv6 = self.host.contains(":") && !self.host.hasPrefix("[")
            let renderedHost = isIPv6 ? "[\(self.host)]" : self.host
            return "http://\(renderedHost):\(self.port)/"
        }
    }

    static func parseServerEndpoint(from args: [String]) -> ServerEndpoint {
        var host = "127.0.0.1"
        var port = 8080

        var idx = 0
        while idx < args.count {
            let arg = args[idx]

            if arg == "--host", idx + 1 < args.count {
                host = args[idx + 1]
                idx += 2
                continue
            }

            if arg.hasPrefix("--host=") {
                host = String(arg.dropFirst("--host=".count))
                idx += 1
                continue
            }

            if arg == "--port", idx + 1 < args.count {
                if let parsed = Int(args[idx + 1]) {
                    port = parsed
                }
                idx += 2
                continue
            }

            if arg.hasPrefix("--port=") {
                if let parsed = Int(arg.dropFirst("--port=".count)) {
                    port = parsed
                }
                idx += 1
                continue
            }

            idx += 1
        }

        return ServerEndpoint(host: host, port: port)
    }

    static func systemdUserUnitURL(serviceName: String) -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("systemd", isDirectory: true)
            .appendingPathComponent("user", isDirectory: true)

        return base.appendingPathComponent("\(serviceName).service")
    }

    static func systemdUserUnit(
        serverPath: String,
        serverArgs: [String],
        cliPath: String,
        pathEnv: String,
        description: String) -> String
    {
        let escapedCLIPath = Self.systemdEscapeEnvValue(cliPath)
        let escapedPATH = Self.systemdEscapeEnvValue(pathEnv)

        let execStart = ([serverPath] + serverArgs)
            .map(Self.systemdEscapeExecArgument)
            .joined(separator: " ")

        return """
        [Unit]
        Description=\(description)
        After=network-online.target

        [Service]
        Type=simple
        Restart=on-failure
        RestartSec=10
        WorkingDirectory=%h
        Environment=\"CODEXBAR_CLI_PATH=\(escapedCLIPath)\"
        Environment=\"PATH=\(escapedPATH)\"
        ExecStart=\(execStart)

        [Install]
        WantedBy=default.target
        """
    }

    static func runSystemctlUser(_ args: [String]) throws {
        guard let systemctlPath = Self.resolveSystemctlPath() else {
            throw SystemctlError.notFound
        }

        let (code, stdout, stderr) = try Self.runProcess(
            executable: systemctlPath,
            arguments: ["--user"] + args)

        guard code == 0 else {
            throw SystemctlError.failed(code: code, stdout: stdout, stderr: stderr)
        }
    }

    private static func resolveSystemctlPath() -> String? {
        if let located = TTYCommandRunner.which("systemctl") {
            return located
        }
        let candidates = ["/usr/bin/systemctl", "/bin/systemctl"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func runProcess(executable: String, arguments: [String]) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout.trimmingCharacters(in: .whitespacesAndNewlines), stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum SystemctlError: LocalizedError {
        case notFound
        case failed(code: Int32, stdout: String, stderr: String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "systemctl not found. This command requires systemd."
            case let .failed(code, stdout, stderr):
                var lines: [String] = ["systemctl failed (exit \(code))"]
                if !stdout.isEmpty { lines.append("stdout: \(stdout)") }
                if !stderr.isEmpty { lines.append("stderr: \(stderr)") }
                return lines.joined(separator: "\n")
            }
        }
    }

    static func systemdEscapeEnvValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func systemdEscapeExecArgument(_ argument: String) -> String {
        // systemd accepts simple double-quote escaping for ExecStart tokenization.
        if argument.isEmpty {
            return "\"\""
        }
        let needsQuotes = argument.contains(where: { $0.isWhitespace }) || argument.contains("\"") || argument.contains("\\")
        guard needsQuotes else {
            return argument
        }
        let escaped = argument
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    #endif
}
