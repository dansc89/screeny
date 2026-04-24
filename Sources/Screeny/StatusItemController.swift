import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let handler: MenuActionHandler

    init(onCaptureFullScreen: @escaping () -> Void, onCaptureInteractive: @escaping () -> Void, onQuit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        handler = MenuActionHandler(
            onCaptureFullScreen: onCaptureFullScreen,
            onCaptureInteractive: onCaptureInteractive,
            onQuit: onQuit
        )

        if let button = statusItem.button {
            button.image = Self.makeMenuBarEyeIcon()
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Full Screen (Cmd+Shift+3)", action: #selector(MenuActionHandler.captureFullScreen), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Area/Window (Cmd+Shift+4, Space for window)", action: #selector(MenuActionHandler.captureInteractive), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Screeny", action: #selector(MenuActionHandler.quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = handler }

        statusItem.menu = menu
    }

    private static func makeMenuBarEyeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let eyeRect = NSRect(x: 2.5, y: 4.0, width: 13.0, height: 10.0)
        let eyePath = NSBezierPath(ovalIn: eyeRect)
        eyePath.lineWidth = 1.5
        NSColor.labelColor.setStroke()
        eyePath.stroke()

        let pupilSize: CGFloat = 2.6
        let pupilRect = NSRect(
            x: (size.width - pupilSize) / 2,
            y: (size.height - pupilSize) / 2 - 0.2,
            width: pupilSize,
            height: pupilSize
        )
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: pupilRect).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

@MainActor
private final class MenuActionHandler: NSObject {
    private let onCaptureFullScreen: () -> Void
    private let onCaptureInteractive: () -> Void
    private let onQuit: () -> Void

    init(onCaptureFullScreen: @escaping () -> Void, onCaptureInteractive: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onCaptureFullScreen = onCaptureFullScreen
        self.onCaptureInteractive = onCaptureInteractive
        self.onQuit = onQuit
    }

    @objc func captureFullScreen() {
        onCaptureFullScreen()
    }

    @objc func captureInteractive() {
        onCaptureInteractive()
    }

    @objc func quit() {
        onQuit()
    }
}
