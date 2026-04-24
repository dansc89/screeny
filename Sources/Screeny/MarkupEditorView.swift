import AppKit
import SwiftUI

struct MarkupEditorView: View {
    @ObservedObject var viewModel: MarkupEditorViewModel
    let onSaveAndCopy: (NSImage) -> Void
    let onCopyOnly: (NSImage) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            GeometryReader { proxy in
                let imageRect = aspectFitRect(for: viewModel.baseImage.size, in: proxy.size)

                ZStack {
                    Color.black.opacity(0.9)
                        .ignoresSafeArea()

                    Image(nsImage: viewModel.baseImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    Canvas { context, _ in
                        drawAnnotations(in: &context, imageRect: imageRect, includePreview: true)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.handleDragChanged(
                                location: value.location,
                                imageRect: imageRect,
                                constrainOrthogonal: isShiftPressed()
                            )
                        }
                        .onEnded { value in
                            viewModel.handleDragEnded(
                                location: value.location,
                                imageRect: imageRect,
                                constrainOrthogonal: isShiftPressed()
                            )
                        }
                )
            }
            .frame(minWidth: 820, minHeight: 520)
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

        case .arrow(let arrow):
            drawArrow(arrow, in: &context, imageRect: imageRect)
        }
    }

    private func drawArrow(_ arrow: ArrowAnnotation, in context: inout GraphicsContext, imageRect: CGRect) {
        let start = denormalized(arrow.start, in: imageRect)
        let end = denormalized(arrow.end, in: imageRect)
        let width = lineWidth(for: arrow.normalizedLineWidth, in: imageRect)

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(shaft, with: .color(arrow.color.swiftUIColor), style: .init(lineWidth: width, lineCap: .round))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(14, width * 3)
        let headAngle: CGFloat = .pi / 6

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
        max(1, normalized * max(imageRect.width, imageRect.height))
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
        case .rectangle:
            return "r"
        case .arrow:
            return "a"
        }
    }

    private func isShiftPressed() -> Bool {
        NSEvent.modifierFlags.contains(.shift)
    }
}
