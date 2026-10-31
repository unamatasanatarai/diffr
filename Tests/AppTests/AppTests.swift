import Foundation

public enum AppTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("AppConfig returns valid non-empty application name") {
            try expect(!AppConfig.appName.isEmpty, "App name should not be empty")
        }

        testRunner("AppConfig returns valid bundle identifier") {
            try expect(!AppConfig.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            try expect(AppConfig.bundleIdentifier.contains("."), "Bundle identifier should be reverse-DNS style")
        }

        testRunner("AppConfig provides version string") {
            try expect(!AppConfig.version.isEmpty, "Version should not be empty")
        }

        testRunner("AppConfig provides build number") {
            try expect(!AppConfig.buildNumber.isEmpty, "Build number should not be empty")
        }

    }
}
