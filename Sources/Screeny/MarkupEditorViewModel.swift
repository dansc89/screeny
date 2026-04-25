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

    func handleDragChanged(location: CGPoint, imageRect: CGRect, constrainOrthogonal: Bool = false) {
        guard let normalized = normalizedPoint(from: location, in: imageRect) else {
            return
        }

        if activeStartPoint == nil {
            activeStartPoint = normalized
            if selectedTool == .pen || selectedTool == .highlighter {
                activeStrokePoints = [normalized]
                if selectedTool == .pen {
                    previewAnnotation = .stroke(
                        StrokeAnnotation(
                            points: activeStrokePoints,
                            color: selectedRGBAColor,
                            normalizedLineWidth: normalizedLineWidth(for: imageRect)
                        )
                    )
                } else {
                    previewAnnotation = .highlighter(
                        HighlighterAnnotation(
                            points: activeStrokePoints,
                            color: highlighterRGBAColor,
                            normalizedLineWidth: normalizedHighlighterLineWidth(for: imageRect)
                        )
                    )
                }
            }
            return
        }

        switch selectedTool {
        case .pen:
            let nextPoint = constrainedPointIfNeeded(normalized, constrainOrthogonal: constrainOrthogonal)
            if constrainOrthogonal, let start = activeStartPoint {
                activeStrokePoints = [start, nextPoint]
            } else {
                activeStrokePoints.append(nextPoint)
            }
            previewAnnotation = .stroke(
                StrokeAnnotation(
                    points: activeStrokePoints,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        case .highlighter:
            let nextPoint = constrainedPointIfNeeded(normalized, constrainOrthogonal: constrainOrthogonal)
            if constrainOrthogonal, let start = activeStartPoint {
                activeStrokePoints = [start, nextPoint]
            } else {
                activeStrokePoints.append(nextPoint)
            }
            previewAnnotation = .highlighter(
                HighlighterAnnotation(
                    points: activeStrokePoints,
                    color: highlighterRGBAColor,
                    normalizedLineWidth: normalizedHighlighterLineWidth(for: imageRect)
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
        case .circle:
            guard let start = activeStartPoint else { return }
            previewAnnotation = .circle(
                CircleAnnotation(
                    start: start,
                    end: normalized,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        case .arrow:
            guard let start = activeStartPoint else { return }
            let nextPoint = constrainedPointIfNeeded(normalized, constrainOrthogonal: constrainOrthogonal)
            previewAnnotation = .arrow(
                ArrowAnnotation(
                    start: start,
                    end: nextPoint,
                    color: selectedRGBAColor,
                    normalizedLineWidth: normalizedLineWidth(for: imageRect)
                )
            )
        }
    }

    func handleDragEnded(location: CGPoint, imageRect: CGRect, constrainOrthogonal: Bool = false) {
        defer {
            activeStartPoint = nil
            activeStrokePoints = []
            previewAnnotation = nil
        }

        guard let rawEnd = normalizedPoint(from: location, in: imageRect, clamped: true) else {
            return
        }
        let end = constrainedPointIfNeeded(rawEnd, constrainOrthogonal: constrainOrthogonal)

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
        case .highlighter:
            guard !activeStrokePoints.isEmpty else {
                return
            }
            if activeStrokePoints.last != end {
                activeStrokePoints.append(end)
            }
            annotations.append(
                .highlighter(
                    HighlighterAnnotation(
                        points: activeStrokePoints,
                        color: highlighterRGBAColor,
                        normalizedLineWidth: normalizedHighlighterLineWidth(for: imageRect)
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
        case .circle:
            guard let start = activeStartPoint, !isNearlySame(start, end) else {
                return
            }
            annotations.append(
                .circle(
                    CircleAnnotation(
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

    private var highlighterRGBAColor: RGBAColor {
        var color = selectedRGBAColor
        color.alpha = min(color.alpha, 0.35)
        return color
    }

    private func normalizedLineWidth(for imageRect: CGRect) -> CGFloat {
        lineWidth / max(imageRect.width, imageRect.height)
    }

    private func normalizedHighlighterLineWidth(for imageRect: CGRect) -> CGFloat {
        (lineWidth * 2.2) / max(imageRect.width, imageRect.height)
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

    private func constrainedPointIfNeeded(_ point: NormalizedPoint, constrainOrthogonal: Bool) -> NormalizedPoint {
        guard
            constrainOrthogonal,
            let start = activeStartPoint,
            selectedTool == .pen || selectedTool == .highlighter || selectedTool == .arrow
        else {
            return point
        }

        let deltaX = point.x - start.x
        let deltaY = point.y - start.y

        if abs(deltaX) >= abs(deltaY) {
            return NormalizedPoint(x: point.x, y: start.y)
        }

        return NormalizedPoint(x: start.x, y: point.y)
    }
}
