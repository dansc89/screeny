import AppKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let screenshotService = ScreenshotService()
    private var markupWindowController: MarkupWindowController?
    private var isCaptureInProgress = false

    func captureFullScreen() {
        startCapture(mode: .fullScreen)
    }

    func captureInteractive() {
        startCapture(mode: .interactive)
    }

    private func startCapture(mode: CaptureMode) {
        guard !isCaptureInProgress else {
            return
        }
        isCaptureInProgress = true

        Task {
            await performCapture(mode: mode)
        }
    }

    private func performCapture(mode: CaptureMode) async {
        defer {
            endCapture()
        }

        do {
            let image = try await screenshotService.capture(mode: mode)
            presentMarkupWindow(for: image)
        } catch ScreenshotServiceError.cancelled {
            return
        } catch ScreenshotServiceError.permissionDenied {
            ScreenCapturePermissionManager.handlePermissionDenied()
            return
        } catch {
            presentError(error)
        }
    }

    private func endCapture() {
        isCaptureInProgress = false
    }
    private func presentMarkupWindow(for image: NSImage) {
        let windowController = MarkupWindowController(
            image: image,
            onSaveAndCopy: { [weak self] renderedImage in
                self?.handleSaveAndCopy(renderedImage)
            },
            onCopyOnly: { [weak self] renderedImage in
                self?.handleCopyOnly(renderedImage)
            }
        )

        markupWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleSaveAndCopy(_ image: NSImage) {
        copyToClipboard(image)
        do {
            try presentSavePanelAndWritePNG(image)
        } catch {
            presentError(error)
        }
    }

    private func handleCopyOnly(_ image: NSImage) {
        copyToClipboard(image)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func presentSavePanelAndWritePNG(_ image: NSImage) throws {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = defaultScreenshotFilename()

        if let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = picturesDirectory
        }

        let response = savePanel.runModal()
        guard response == .OK, let destination = savePanel.url else {
            return
        }

        guard
            let tiffData = image.tiffRepresentation,
            let imageRep = NSBitmapImageRep(data: tiffData),
            let pngData = imageRep.representation(using: .png, properties: [:])
        else {
            throw ScreenshotServiceError.invalidImage
        }

        try pngData.write(to: destination, options: .atomic)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Screeny Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func defaultScreenshotFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }
}
