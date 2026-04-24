import AppKit
import Foundation

enum CaptureMode {
    case fullScreen
    case interactive
}

enum ScreenshotServiceError: Error {
    case cancelled
    case permissionDenied(details: String?)
    case captureFailed(status: Int32, details: String?)
    case missingOutput(details: String?)
    case invalidImage
}

extension ScreenshotServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screenshot was cancelled."
        case .permissionDenied(let details):
            if let details, !details.isEmpty {
                return "Screen recording permission is required. \(details)"
            }
            return "Screen recording permission is required for capture."
        case .captureFailed(let status, let details):
            if let details, !details.isEmpty {
                return "Screenshot capture failed (\(status)): \(details)"
            }
            return "Screenshot capture failed with status \(status)."
        case .missingOutput(let details):
            if let details, !details.isEmpty {
                return "Screenshot capture did not produce a file. \(details)"
            }
            return "Screenshot capture did not produce a file. This can happen if capture was canceled."
        case .invalidImage:
            return "Captured screenshot could not be decoded."
        }
    }
}

struct ScreenshotService: Sendable {
    func capture(mode: CaptureMode) async throws -> NSImage {
        let outputURL = makeTemporaryOutputURL()
        try await runCaptureProcess(mode: mode, outputURL: outputURL)

        guard let data = try? Data(contentsOf: outputURL), let image = NSImage(data: data) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ScreenshotServiceError.invalidImage
        }

        try? FileManager.default.removeItem(at: outputURL)
        return image
    }

    private func runCaptureProcess(mode: CaptureMode, outputURL: URL) async throws {
        let arguments = arguments(for: mode, outputURL: outputURL)
        try? FileManager.default.removeItem(at: outputURL)

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                let errorPipe = Pipe()
                process.standardError = errorPipe

                process.terminationHandler = { finished in
                    let fileExists = waitForFileCreation(at: outputURL.path, timeout: 0.8)
                    let stderrText = readPipe(errorPipe)

                    if finished.terminationStatus == 0, fileExists {
                        continuation.resume()
                        return
                    }

                    if indicatesPermissionIssue(stderrText) {
                        continuation.resume(throwing: ScreenshotServiceError.permissionDenied(details: stderrText))
                        return
                    }

                    // In interactive mode, no file generally means cancel/escape/window deselection.
                    if mode == .interactive, !fileExists {
                        continuation.resume(throwing: ScreenshotServiceError.cancelled)
                        return
                    }

                    if finished.terminationStatus != 0 {
                        continuation.resume(throwing: ScreenshotServiceError.captureFailed(status: finished.terminationStatus, details: stderrText))
                        return
                    }

                    if !fileExists {
                        continuation.resume(throwing: ScreenshotServiceError.missingOutput(details: stderrText))
                        return
                    }

                    continuation.resume(throwing: ScreenshotServiceError.captureFailed(status: finished.terminationStatus, details: stderrText))
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func arguments(for mode: CaptureMode, outputURL: URL) -> [String] {
        var arguments = ["-x"]

        switch mode {
        case .fullScreen:
            break
        case .interactive:
            arguments.append("-i")
        }

        arguments.append(outputURL.path)
        return arguments
    }

    private func makeTemporaryOutputURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "screeny-\(formatter.string(from: Date()))-\(UUID().uuidString).png"
        return directory.appendingPathComponent(filename)
    }
}

private func waitForFileCreation(at path: String, timeout: TimeInterval) -> Bool {
    if FileManager.default.fileExists(atPath: path) {
        return true
    }

    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        usleep(50_000)
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
    }
    return false
}

private func readPipe(_ pipe: Pipe) -> String? {
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard !data.isEmpty else {
        return nil
    }
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func indicatesPermissionIssue(_ text: String?) -> Bool {
    guard let text else {
        return false
    }

    let normalized = text.lowercased()
    return normalized.contains("screen recording")
        || normalized.contains("screen capture access")
        || normalized.contains("not authorized to capture")
        || normalized.contains("not permitted to capture")
        || normalized.contains("request screen capture access")
        || normalized.contains("tcc")
}
