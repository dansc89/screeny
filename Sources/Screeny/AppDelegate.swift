import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hotKeyManager: HotKeyManager?
    private var captureCoordinator: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureLaunchAtLogin()

        let coordinator = CaptureCoordinator()
        captureCoordinator = coordinator

        statusItemController = StatusItemController(
            onCaptureFullScreen: { coordinator.captureFullScreen() },
            onCaptureInteractive: { coordinator.captureInteractive() },
            onQuit: { NSApp.terminate(nil) }
        )

        let hotKeys = HotKeyManager()
        hotKeys.registerDefaultHotKeys(
            fullScreenHandler: { coordinator.captureFullScreen() },
            interactiveHandler: { coordinator.captureInteractive() }
        )
        hotKeyManager = hotKeys
    }

    private func configureLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.ensureEnabledForCurrentExecutable()
        } catch {
            NSLog("Screeny failed to configure launch at login: \(error.localizedDescription)")
        }
    }
}
