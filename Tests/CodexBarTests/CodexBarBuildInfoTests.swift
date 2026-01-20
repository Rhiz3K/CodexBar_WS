import CodexBarCore
import Testing

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite(.serialized)
struct CodexBarBuildInfoTests {
    private func withEnv<T>(_ key: String, _ value: String?, operation: () -> T) -> T {
        let previous = key.withCString { keyPtr in
            getenv(keyPtr).map { String(cString: $0) }
        }

        func set(_ value: String) {
            _ = key.withCString { keyPtr in
                value.withCString { valuePtr in
                    setenv(keyPtr, valuePtr, 1)
                }
            }
        }

        func unset() {
            _ = key.withCString { keyPtr in
                unsetenv(keyPtr)
            }
        }

        if let value {
            set(value)
        } else {
            unset()
        }
        defer {
            if let previous {
                set(previous)
            } else {
                unset()
            }
        }
        return operation()
    }

    @Test
    func versionStringPrefersExplicitVersionString() {
        self.withEnv("CODEXBAR_VERSION_STRING", "1.2.3-custom") {
            #expect(CodexBarBuildInfo.versionString == "1.2.3-custom")
        }
    }

    @Test
    func versionStringBuildsFromAppVersionAndBuildNumber() {
        self.withEnv("CODEXBAR_VERSION_STRING", nil) {
            self.withEnv("CODEXBAR_APP_VERSION", "1.2.3") {
                self.withEnv("CODEXBAR_BUILD_NUMBER", "42") {
                #expect(CodexBarBuildInfo.versionString == "1.2.3 (42)")
                }
            }
        }
    }

    @Test
    func versionStringSupportsAppVersionWithoutBuildNumber() {
        self.withEnv("CODEXBAR_VERSION_STRING", nil) {
            self.withEnv("CODEXBAR_APP_VERSION", "1.2.3") {
                self.withEnv("CODEXBAR_BUILD_NUMBER", nil) {
                #expect(CodexBarBuildInfo.versionString == "1.2.3")
                }
            }
        }
    }
}
