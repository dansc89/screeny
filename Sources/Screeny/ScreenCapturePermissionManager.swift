import AppKit
import CoreGraphics

@MainActor
enum ScreenCapturePermissionManager {
    private static var hasShownPermissionAlertThisSession = false

    static func handlePermissionDenied() {
        _ = CGRequestScreenCaptureAccess()
        guard !CGPreflightScreenCaptureAccess() else {
            return
        }

        if !hasShownPermissionAlertThisSession {
            hasShownPermissionAlertThisSession = true
            presentPermissionAlert()
        }
    }

    private static func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Screeny needs Screen Recording permission to capture screenshots.

        If Screeny already appears as enabled, disable and re-enable it in Privacy settings, then fully quit and reopen Screeny.
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
