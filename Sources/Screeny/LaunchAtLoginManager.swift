import Foundation

enum LaunchAtLoginError: LocalizedError {
    case missingBundlePath
    case serializationFailed
    case launchctlFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .missingBundlePath:
            return "Unable to determine Screeny's app bundle path."
        case .serializationFailed:
            return "Failed to serialize LaunchAgent configuration."
        case .launchctlFailed(let message):
            return "Failed to register LaunchAgent: \(message)"
        }
    }
}

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let label = "com.screeny.launchagent"

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private init() {}

    func ensureEnabledForCurrentExecutable() throws {
        // Only configure launch-at-login when running from a proper .app bundle.
        guard let bundlePath = resolvedBundlePath() else {
            return
        }

        if try needsPlistUpdate(for: bundlePath) {
            try writeLaunchAgentPlist(bundlePath: bundlePath)
        }

        try reloadLaunchAgent()
    }

    private func resolvedBundlePath() -> String? {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard bundleURL.pathExtension == "app" else {
            return nil
        }
        let bundlePath = bundleURL.path
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            return nil
        }
        return bundlePath
    }

    private func expectedProgramArguments(for bundlePath: String) -> [String] {
        ["/usr/bin/open", "-a", bundlePath]
    }

    private func needsPlistUpdate(for bundlePath: String) throws -> Bool {
        let expectedArguments = expectedProgramArguments(for: bundlePath)
        guard let data = try? Data(contentsOf: launchAgentURL) else {
            return true
        }

        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard
            let dictionary = plist as? [String: Any],
            let programArguments = dictionary["ProgramArguments"] as? [String]
        else {
            return true
        }

        return programArguments != expectedArguments
    }

    private func writeLaunchAgentPlist(bundlePath: String) throws {
        let programArguments = expectedProgramArguments(for: bundlePath)

        let directory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]

        guard PropertyListSerialization.propertyList(plist, isValidFor: .xml) else {
            throw LaunchAtLoginError.serializationFailed
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private func reloadLaunchAgent() throws {
        let userDomain = "gui/\(getuid())"
        _ = try runLaunchctl(arguments: ["bootout", userDomain, launchAgentURL.path], allowFailure: true)
        _ = try runLaunchctl(arguments: ["bootstrap", userDomain, launchAgentURL.path], allowFailure: false)
    }

    @discardableResult
    private func runLaunchctl(arguments: [String], allowFailure: Bool) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 || allowFailure {
            return process.terminationStatus
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw LaunchAtLoginError.launchctlFailed(message: message ?? "launchctl exited with status \(process.terminationStatus)")
    }
}
