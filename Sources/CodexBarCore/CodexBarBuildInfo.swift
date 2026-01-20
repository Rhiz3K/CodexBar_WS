import Foundation

public enum CodexBarBuildInfo {
    public static var versionString: String? {
        let env = ProcessInfo.processInfo.environment

        if let versionString = env["CODEXBAR_VERSION_STRING"], !versionString.isEmpty {
            return versionString
        }

        let marketingVersion =
            env["CODEXBAR_APP_VERSION"]
            ?? env["CODEXBAR_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        guard let marketingVersion, !marketingVersion.isEmpty else { return nil }

        let buildNumber =
            env["CODEXBAR_BUILD_NUMBER"]
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        if let buildNumber, !buildNumber.isEmpty {
            return "\(marketingVersion) (\(buildNumber))"
        }

        return marketingVersion
    }
}
