import AppKit
import SwiftUI

struct MarkupEditorView: View {
    @ObservedObject var viewModel: MarkupEditorViewModel
    let onSaveAndCopy: (NSImage) -> Void
    let onCopyOnly: (NSImage) -> Void
    let onClose: () -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchStartZoomScale: CGFloat = 1.0
    @State private var isPinching = false
    @State private var scrollViewReference: NSScrollView?
    @State private var wheelEventMonitor: Any?
    @State private var middleMouseDownMonitor: Any?
    @State private var middleMouseDragMonitor: Any?
    @State private var middleMouseUpMonitor: Any?
    @State private var escapeKeyMonitor: Any?
    @State private var middlePanLastPointInWindow: CGPoint?
    @State private var didPushMiddlePanCursor = false

    private let minZoomScale: CGFloat = 0.5
    private let maxZoomScale: CGFloat = 6.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            GeometryReader { proxy in
                let canvasSize = proxy.size
                let imageRect = aspectFitRect(for: viewModel.baseImage.size, in: canvasSize)

                ScrollView([.horizontal, .vertical]) {
                    Color.black.opacity(0.9)
                        .overlay(alignment: .center) {
                            ZStack {
                                Image(nsImage: viewModel.baseImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: canvasSize.width, height: canvasSize.height)

                                Canvas { context, _ in
                                    drawAnnotations(in: &context, imageRect: imageRect, includePreview: true)
                                }
                                .frame(width: canvasSize.width, height: canvasSize.height)
                            }
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        viewModel.handleDragChanged(
                                            location: effectiveCanvasLocation(from: value.location),
                                            imageRect: imageRect,
                                            constrainOrthogonal: isShiftPressed()
                                        )
                                    }
                                    .onEnded { value in
                                        viewModel.handleDragEnded(
                                            location: effectiveCanvasLocation(from: value.location),
                                            imageRect: imageRect,
                                            constrainOrthogonal: isShiftPressed()
                                        )
                                    }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { magnification in
                                        if !isPinching {
                                            pinchStartZoomScale = zoomScale
                                            isPinching = true
                                        }
                                        applyZoom(clampedZoom(pinchStartZoomScale * magnification))
                                    }
                                    .onEnded { _ in
                                        isPinching = false
                                    }
                            )
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
                .background(
                    ScrollViewAccessor { scrollView in
                        scrollViewReference = scrollView
                        configureScrollViewForZoom(scrollView)
                    }
                )
                .background(Color.black.opacity(0.9).ignoresSafeArea())
            }
            .frame(minWidth: 820, minHeight: 520)
        }
        .onAppear {
            installWheelZoomMonitorIfNeeded()
            installMiddleMousePanMonitorsIfNeeded()
            installEscapeKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeWheelZoomMonitor()
            removeMiddleMousePanMonitors()
            removeEscapeKeyMonitor()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(MarkupTool.allCases) { tool in
                    Button {
                        viewModel.selectedTool = tool
                    } label: {
                        Label(tool.displayName, systemImage: tool.symbolName)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.selectedTool == tool ? .accentColor : .gray.opacity(0.45))
                    .keyboardShortcut(toolKeyEquivalent(tool), modifiers: [])
                }
            }

            Divider()
                .frame(height: 20)

            ColorPicker("Color", selection: $viewModel.selectedColor, supportsOpacity: true)
                .labelsHidden()

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                Slider(value: $viewModel.lineWidth, in: 1...20)
                    .frame(width: 140)
                Text("\(Int(viewModel.lineWidth))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 26)
            }

            Button("Undo") {
                viewModel.undoLast()
            }
            .keyboardShortcut("z", modifiers: [.command])

            Button("Clear") {
                viewModel.clearAll()
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 6) {
                Button {
                    zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: [.command])

                Text("\(Int((zoomScale * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)

                Button {
                    zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Fit") {
                    resetZoom()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            Spacer()

            Button("Close") {
                onClose()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Copy") {
                onCopyOnly(currentRenderedImage())
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Save + Copy") {
                onSaveAndCopy(currentRenderedImage())
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func drawAnnotations(in context: inout GraphicsContext, imageRect: CGRect, includePreview: Bool) {
        for annotation in viewModel.annotations {
            draw(annotation: annotation, in: &context, imageRect: imageRect)
        }

        if includePreview, let preview = viewModel.previewAnnotation {
            draw(annotation: preview, in: &context, imageRect: imageRect)
        }
    }

    private func draw(annotation: Annotation, in context: inout GraphicsContext, imageRect: CGRect) {
        switch annotation {
        case .stroke(let stroke):
            guard stroke.points.count > 1 else { return }
            var path = Path()
            path.move(to: denormalized(stroke.points[0], in: imageRect))
            for point in stroke.points.dropFirst() {
                path.addLine(to: denormalized(point, in: imageRect))
            }
            context.stroke(path, with: .color(stroke.color.swiftUIColor), style: .init(lineWidth: lineWidth(for: stroke.normalizedLineWidth, in: imageRect), lineCap: .round, lineJoin: .round))
        case .highlighter(let highlighter):
            guard highlighter.points.count > 1 else { return }
            var path = Path()
            path.move(to: denormalized(highlighter.points[0], in: imageRect))
            for point in highlighter.points.dropFirst() {
                path.addLine(to: denormalized(point, in: imageRect))
            }
            context.blendMode = .multiply
            context.stroke(path, with: .color(highlighter.color.swiftUIColor), style: .init(lineWidth: lineWidth(for: highlighter.normalizedLineWidth, in: imageRect), lineCap: .round, lineJoin: .round))
            context.blendMode = .normal

        case .rectangle(let rectangle):
            let p1 = denormalized(rectangle.start, in: imageRect)
            let p2 = denormalized(rectangle.end, in: imageRect)
            let rect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: abs(p1.x - p2.x),
                height: abs(p1.y - p2.y)
            )
            var path = Path()
            path.addRect(rect)
            context.stroke(path, with: .color(rectangle.color.swiftUIColor), lineWidth: lineWidth(for: rectangle.normalizedLineWidth, in: imageRect))

        case .circle(let circle):
            let p1 = denormalized(circle.start, in: imageRect)
            let p2 = denormalized(circle.end, in: imageRect)
            let rect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: abs(p1.x - p2.x),
                height: abs(p1.y - p2.y)
            )
            var path = Path()
            path.addEllipse(in: rect)
            context.stroke(path, with: .color(circle.color.swiftUIColor), lineWidth: lineWidth(for: circle.normalizedLineWidth, in: imageRect))

        case .arrow(let arrow):
            drawArrow(arrow, in: &context, imageRect: imageRect)
        }
    }

    private func drawArrow(_ arrow: ArrowAnnotation, in context: inout GraphicsContext, imageRect: CGRect) {
        let start = denormalized(arrow.start, in: imageRect)
        let end = denormalized(arrow.end, in: imageRect)
        let width = lineWidth(for: arrow.normalizedLineWidth, in: imageRect)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }
        let unitX = dx / length
        let unitY = dy / length

        let angle = atan2(dy, dx)
        let headLength = min(max(14, width * 3), length * 0.9)
        let headAngle: CGFloat = .pi / 6
        let shaftEnd = CGPoint(
            x: end.x - unitX * headLength * 0.82,
            y: end.y - unitY * headLength * 0.82
        )

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(arrow.color.swiftUIColor), style: .init(lineWidth: width, lineCap: .round))

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        var head = Path()
        head.move(to: end)
        head.addLine(to: p1)
        head.addLine(to: p2)
        head.closeSubpath()
        context.fill(head, with: .color(arrow.color.swiftUIColor))
    }

    private func lineWidth(for normalized: CGFloat, in imageRect: CGRect) -> CGFloat {
        let base = normalized * max(imageRect.width, imageRect.height)
        let magnification = scrollViewReference?.magnification ?? zoomScale
        return max(1, base * magnification)
    }

    private func denormalized(_ point: NormalizedPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + point.y * imageRect.height
        )
    }

    private func aspectFitRect(for imageSize: CGSize, in availableSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, availableSize.width > 0, availableSize.height > 0 else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = availableSize.width / availableSize.height

        if imageAspect > containerAspect {
            let width = availableSize.width
            let height = width / imageAspect
            let y = (availableSize.height - height) / 2
            return CGRect(x: 0, y: y, width: width, height: height)
        }

        let height = availableSize.height
        let width = height * imageAspect
        let x = (availableSize.width - width) / 2
        return CGRect(x: x, y: 0, width: width, height: height)
    }

    private func currentRenderedImage() -> NSImage {
        viewModel.renderedImage() ?? viewModel.baseImage
    }

    private func toolKeyEquivalent(_ tool: MarkupTool) -> KeyEquivalent {
        switch tool {
        case .pen:
            return "p"
        case .highlighter:
            return "h"
        case .rectangle:
            return "r"
        case .circle:
            return "c"
        case .arrow:
            return "a"
        }
    }

    private func isShiftPressed() -> Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoomScale), maxZoomScale)
    }

    private func zoomIn() {
        applyZoom(clampedZoom(zoomScale * 1.2))
    }

    private func zoomOut() {
        applyZoom(clampedZoom(zoomScale / 1.2))
    }

    private func resetZoom() {
        applyZoom(1.0)
    }

    private func installWheelZoomMonitorIfNeeded() {
        guard wheelEventMonitor == nil else {
            return
        }

        wheelEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleWheelZoomEvent(event)
        }
    }

    private func removeWheelZoomMonitor() {
        guard let monitor = wheelEventMonitor else {
            return
        }
        NSEvent.removeMonitor(monitor)
        wheelEventMonitor = nil
    }

    private func installMiddleMousePanMonitorsIfNeeded() {
        guard middleMouseDownMonitor == nil, middleMouseDragMonitor == nil, middleMouseUpMonitor == nil else {
            return
        }

        middleMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            handleMiddleMouseDown(event)
        }
        middleMouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { event in
            handleMiddleMouseDragged(event)
        }
        middleMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            handleMiddleMouseUp(event)
        }
    }

    private func removeMiddleMousePanMonitors() {
        if let monitor = middleMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            middleMouseDownMonitor = nil
        }
        if let monitor = middleMouseDragMonitor {
            NSEvent.removeMonitor(monitor)
            middleMouseDragMonitor = nil
        }
        if let monitor = middleMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            middleMouseUpMonitor = nil
        }
        middlePanLastPointInWindow = nil
        if didPushMiddlePanCursor {
            NSCursor.pop()
            didPushMiddlePanCursor = false
        }
    }

    private func handleMiddleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2 else {
            return event
        }

        guard
            let scrollView = resolvedScrollView(for: event),
            let window = event.window ?? scrollView.window
        else {
            return event
        }

        let pointInWindow = event.locationInWindow
        guard
            let hitView = window.contentView?.hitTest(pointInWindow),
            hitView.isDescendant(of: scrollView) || hitView === scrollView
        else {
            return event
        }

        middlePanLastPointInWindow = pointInWindow
        if !didPushMiddlePanCursor {
            NSCursor.closedHand.push()
            didPushMiddlePanCursor = true
        }
        return nil
    }

    private func handleMiddleMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2 else {
            return event
        }
        guard
            let lastPoint = middlePanLastPointInWindow,
            let scrollView = resolvedScrollView(for: event),
            let clipView = scrollView.contentView as NSClipView?,
            let documentView = scrollView.documentView
        else {
            return event
        }

        let currentPoint = event.locationInWindow
        let lastInDocument = documentView.convert(lastPoint, from: nil)
        let currentInDocument = documentView.convert(currentPoint, from: nil)
        let dx = currentInDocument.x - lastInDocument.x
        let dy = currentInDocument.y - lastInDocument.y

        let maxOriginX = max(0, documentView.bounds.width - clipView.bounds.width)
        let maxOriginY = max(0, documentView.bounds.height - clipView.bounds.height)
        var nextOrigin = clipView.bounds.origin
        nextOrigin.x = min(max(0, nextOrigin.x - dx), maxOriginX)
        nextOrigin.y = min(max(0, nextOrigin.y - dy), maxOriginY)

        clipView.setBoundsOrigin(nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
        middlePanLastPointInWindow = currentPoint
        return nil
    }

    private func handleMiddleMouseUp(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2 else {
            return event
        }
        middlePanLastPointInWindow = nil
        if didPushMiddlePanCursor {
            NSCursor.pop()
            didPushMiddlePanCursor = false
        }
        return nil
    }

    private func installEscapeKeyMonitorIfNeeded() {
        guard escapeKeyMonitor == nil else {
            return
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }
            guard
                let scrollView = scrollViewReference,
                let window = scrollView.window,
                event.window === window || event.window == nil
            else {
                return event
            }
            onClose()
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        guard let monitor = escapeKeyMonitor else {
            return
        }
        NSEvent.removeMonitor(monitor)
        escapeKeyMonitor = nil
    }

    private func handleWheelZoomEvent(_ event: NSEvent) -> NSEvent? {
        guard let scrollView = resolvedScrollView(for: event) else {
            return event
        }
        configureScrollViewForZoom(scrollView)

        guard let clipView = scrollView.contentView as NSClipView? else {
            return event
        }

        guard
            let documentView = scrollView.documentView,
            let window = event.window ?? scrollView.window
        else {
            return event
        }

        let pointInWindow: CGPoint
        if event.window != nil {
            pointInWindow = event.locationInWindow
        } else {
            pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        }

        guard
            let hitView = window.contentView?.hitTest(pointInWindow),
            hitView.isDescendant(of: scrollView) || hitView === scrollView
        else {
            return event
        }

        let locationInClipBounds = clipView.convert(pointInWindow, from: nil)
        let anchorInClip = CGPoint(
            x: locationInClipBounds.x - clipView.bounds.origin.x,
            y: locationInClipBounds.y - clipView.bounds.origin.y
        )
        guard
            anchorInClip.x >= 0, anchorInClip.x <= clipView.bounds.width,
            anchorInClip.y >= 0, anchorInClip.y <= clipView.bounds.height
        else {
            return event
        }

        let deltaY = event.scrollingDeltaY
        let deltaX = event.scrollingDeltaX
        let delta = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        guard delta != 0 else {
            return event
        }

        if event.hasPreciseScrollingDeltas, event.momentumPhase != [] {
            return nil
        }

        let magnitude = abs(delta)
        let zoomStep: CGFloat
        if event.hasPreciseScrollingDeltas {
            // Trackpad/precise input: smooth acceleration.
            zoomStep = pow(1.008, max(1.0, min(80.0, magnitude)))
        } else {
            // Mouse wheel notches: slightly stronger per-notch step.
            zoomStep = pow(1.12, max(1.0, min(8.0, magnitude)))
        }

        let factor = delta > 0 ? zoomStep : (1.0 / zoomStep)
        let targetZoom = clampedZoom(zoomScale * factor)
        guard abs(targetZoom - zoomScale) > 0.0001 else {
            return nil
        }

        let anchorInDocument = documentView.convert(pointInWindow, from: nil)
        applyZoom(targetZoom, centeredAt: anchorInDocument, in: scrollView)

        return nil
    }

    private func configureScrollViewForZoom(_ scrollView: NSScrollView) {
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minZoomScale
        scrollView.maxMagnification = maxZoomScale
        let target = clampedZoom(zoomScale)
        if abs(scrollView.magnification - target) > 0.0001 {
            scrollView.setMagnification(target, centeredAt: centerPointInDocument(for: scrollView))
        }
    }

    private func centerPointInDocument(for scrollView: NSScrollView) -> CGPoint {
        CGPoint(
            x: scrollView.contentView.bounds.midX,
            y: scrollView.contentView.bounds.midY
        )
    }

    private func applyZoom(_ target: CGFloat, centeredAt anchor: CGPoint? = nil, in scrollViewOverride: NSScrollView? = nil) {
        let clampedTarget = clampedZoom(target)
        guard let scrollView = scrollViewOverride ?? scrollViewReference else {
            zoomScale = clampedTarget
            return
        }
        configureScrollViewForZoom(scrollView)
        let center = anchor ?? centerPointInDocument(for: scrollView)
        scrollView.setMagnification(clampedTarget, centeredAt: center)
        zoomScale = scrollView.magnification
    }

    private func effectiveCanvasLocation(from gestureLocation: CGPoint) -> CGPoint {
        guard
            let scrollView = scrollViewReference,
            let documentView = scrollView.documentView,
            let window = scrollView.window
        else {
            return gestureLocation
        }

        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return documentView.convert(pointInWindow, from: nil)
    }

    private func resolvedScrollView(for event: NSEvent) -> NSScrollView? {
        if let existing = scrollViewReference {
            return existing
        }

        guard let window = event.window, let contentView = window.contentView else {
            return nil
        }

        if let fallback = firstScrollView(in: contentView) {
            scrollViewReference = fallback
            return fallback
        }

        return nil
    }

    private func firstScrollView(in root: NSView) -> NSScrollView? {
        if let scrollView = root as? NSScrollView {
            return scrollView
        }

        for subview in root.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }

        return nil
    }
}

private struct ScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                onResolve(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                onResolve(scrollView)
            }
        }
    }
}
