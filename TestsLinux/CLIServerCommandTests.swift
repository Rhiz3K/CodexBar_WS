@testable import CodexBarCLI
import Testing

@Suite
struct CLIServerCommandTests {
    @Test
    func parseServerEndpoint_defaults() {
        let endpoint = CodexBarCLI.parseServerEndpoint(from: [])
        #expect(endpoint.host == "127.0.0.1")
        #expect(endpoint.port == 8080)
        #expect(endpoint.dashboardURL == "http://127.0.0.1:8080/")
    }

    @Test
    func parseServerEndpoint_parsesHostAndPort() {
        let endpoint = CodexBarCLI.parseServerEndpoint(from: ["--host", "0.0.0.0", "--port", "9000"]) 
        #expect(endpoint.host == "0.0.0.0")
        #expect(endpoint.port == 9000)
        #expect(endpoint.dashboardURL == "http://0.0.0.0:9000/")
    }

    @Test
    func parseServerEndpoint_parsesEqualsForms() {
        let endpoint = CodexBarCLI.parseServerEndpoint(from: ["--host=127.0.0.1", "--port=9001"]) 
        #expect(endpoint.host == "127.0.0.1")
        #expect(endpoint.port == 9001)
    }

    @Test
    func systemdEscapeExecArgument_quotesWhitespace() {
        let escaped = CodexBarCLI.systemdEscapeExecArgument("/path/with space/bin")
        #expect(escaped == "\"/path/with space/bin\"")
    }

    @Test
    func systemdEscapeEnvValue_escapesQuotes() {
        let escaped = CodexBarCLI.systemdEscapeEnvValue("a\"b")
        #expect(escaped == "a\\\"b")
    }
}
