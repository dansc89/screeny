import AppKit
import SwiftUI

@MainActor
final class MarkupWindowController: NSWindowController, NSWindowDelegate {
    private enum CompletionAction {
        case saveAndCopy
        case copyOnly
    }

    private let viewModel: MarkupEditorViewModel
    private let hostingController: NSHostingController<AnyView>
    private let onSaveAndCopy: (NSImage) -> Void
    private let onCopyOnly: (NSImage) -> Void
    private var hasCompletedAction = false

    init(image: NSImage, onSaveAndCopy: @escaping (NSImage) -> Void, onCopyOnly: @escaping (NSImage) -> Void) {
        viewModel = MarkupEditorViewModel(baseImage: image)
        hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        self.onSaveAndCopy = onSaveAndCopy
        self.onCopyOnly = onCopyOnly
        let initialFrame = Self.preferredWindowFrame()

        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Screeny - Edit Screenshot"
        window.contentViewController = hostingController
        window.setFrame(initialFrame, display: true)
        window.minSize = NSSize(width: 1200, height: 820)

        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self

        hostingController.rootView = AnyView(
            MarkupEditorView(
                viewModel: viewModel,
                onSaveAndCopy: { [weak self] rendered in
                    self?.complete(with: rendered, action: .saveAndCopy)
                },
                onCopyOnly: { [weak self] rendered in
                    self?.complete(with: rendered, action: .copyOnly)
                },
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        // If the window closes via titlebar close or Escape, preserve work by copying.
        if !hasCompletedAction {
            complete(with: viewModel.renderedImage() ?? viewModel.baseImage, action: .copyOnly, shouldClose: false)
        }
    }

    private func complete(with image: NSImage, action: CompletionAction, shouldClose: Bool = true) {
        guard !hasCompletedAction else {
            return
        }
        hasCompletedAction = true

        switch action {
        case .saveAndCopy:
            onSaveAndCopy(image)
        case .copyOnly:
            onCopyOnly(image)
        }

        if shouldClose {
            close()
        }
    }

    private static func preferredWindowFrame() -> CGRect {
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visibleFrame = activeScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1728, height: 1117)

        // Default to almost the entire usable display so markup is immediately readable.
        return visibleFrame.insetBy(dx: 8, dy: 8)
    }
}
