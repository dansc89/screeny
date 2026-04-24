import AppKit
import SwiftUI

final class MarkupEditorViewModel: ObservableObject {
    let baseImage: NSImage

    @Published var selectedTool: MarkupTool = .pen
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 4

    @Published private(set) var annotations: [Annotation] = []
    @Published private(set) var previewAnnotation: Annotation?

    private var activeStartPoint: NormalizedPoint?
    private var activeStrokePoints: [NormalizedPoint] = []

    init(baseImage: NSImage) {
        self.baseImage = baseImage
    }

    func handleDragChanged(location: CGPoint, imageRect: CGRect) {
        guard let normalized = normalizedPoint(from: location, in: imageRect) else {
            return
        }

        if activeStartPoint == nil {
            activeStartPoint = normalized
            if selectedTool == .pen {
                activeStrokePoints = [normalized]
                previewAnnotation = .stroke(
                    StrokeAnnotation(
                        points: activeStrokePoints,
                        color: selectedRGBAColor,
                        normalizedLineWidth: normalizedLineWidth(for: imageRect)
                    )
                )
            }
            return
        }

        switch selectedTool {
        case .pen:
            activeStrokePoints.append(normalized)
            previewAnnotation = .stroke(
                StrokeAnnotation(
                    points: activeStrokePoints,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        case .rectangle:
            guard let start = activeStartPoint else { return }
            previewAnnotation = .rectangle(
                RectangleAnnotation(
                    start: start,
                    end: normalized,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        case .arrow:
            guard let start = activeStartPoint else { return }
            previewAnnotation = .arrow(
                ArrowAnnotation(
                    start: start,
                    end: normalized,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        }
    }

    func handleDragEnded(location: CGPoint, imageRect: CGRect) {
        defer {
            activeStartPoint = nil
            activeStrokePoints = []
            previewAnnotation = nil
        }

        guard let end = normalizedPoint(from: location, in: imageRect, clamped: true) else {
            return
        }

        switch selectedTool {
        case .pen:
            guard !activeStrokePoints.isEmpty else {
                return
            }
            if activeStrokePoints.last != end {
                activeStrokePoints.append(end)
            }
            annotations.append(
                .stroke(
                    StrokeAnnotation(
                        points: activeStrokePoints,
                        color: selectedRGBAColor,
                        normalizedLineWidth: normalizedLineWidth(for: imageRect)
                    )
                )
            )
        case .rectangle:
            guard let start = activeStartPoint, !isNearlySame(start, end) else {
                return
            }
            annotations.append(
                .rectangle(
                    RectangleAnnotation(
                        start: start,
                        end: end,
                        color: selectedRGBAColor,
                        normalizedLineWidth: normalizedLineWidth(for: imageRect)
                    )
                )
            )
        case .arrow:
            guard let start = activeStartPoint, !isNearlySame(start, end) else {
                return
            }
            annotations.append(
                .arrow(
                    ArrowAnnotation(
                        start: start,
                        end: end,
                        color: selectedRGBAColor,
                        normalizedLineWidth: normalizedLineWidth(for: imageRect)
                    )
                )
            )
        }
    }

    func undoLast() {
        guard !annotations.isEmpty else {
            return
        }
        _ = annotations.popLast()
    }

    func clearAll() {
        annotations.removeAll()
        previewAnnotation = nil
        activeStartPoint = nil
        activeStrokePoints = []
    }

    func renderedImage() -> NSImage? {
        MarkupRenderer.render(baseImage: baseImage, annotations: annotations)
    }

    private var selectedRGBAColor: RGBAColor {
        RGBAColor(nsColor: NSColor(selectedColor))
    }

    private func normalizedLineWidth(for imageRect: CGRect) -> CGFloat {
        lineWidth / max(imageRect.width, imageRect.height)
    }

    private func normalizedPoint(from location: CGPoint, in imageRect: CGRect, clamped: Bool = false) -> NormalizedPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return nil
        }

        let x = (location.x - imageRect.minX) / imageRect.width
        let y = (location.y - imageRect.minY) / imageRect.height

        if clamped {
            return NormalizedPoint(x: x, y: y)
        }

        guard (0...1).contains(x), (0...1).contains(y) else {
            return nil
        }

        return NormalizedPoint(x: x, y: y)
    }

    private func isNearlySame(_ lhs: NormalizedPoint, _ rhs: NormalizedPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.002 && abs(lhs.y - rhs.y) < 0.002
    }
}
