import AppKit
import SwiftUI

struct RGBAColor {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let rgbColor = nsColor.usingColorSpace(.deviceRGB) ?? .systemRed
        red = rgbColor.redComponent
        green = rgbColor.greenComponent
        blue = rgbColor.blueComponent
        alpha = rgbColor.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

struct NormalizedPoint: Equatable {
    var x: CGFloat
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

struct StrokeAnnotation: Identifiable {
    let id = UUID()
    var points: [NormalizedPoint]
    var color: RGBAColor
    var normalizedLineWidth: CGFloat
}

struct RectangleAnnotation: Identifiable {
    let id = UUID()
    var start: NormalizedPoint
    var end: NormalizedPoint
    var color: RGBAColor
    var normalizedLineWidth: CGFloat
}

struct CircleAnnotation: Identifiable {
    let id = UUID()
    var start: NormalizedPoint
    var end: NormalizedPoint
    var color: RGBAColor
    var normalizedLineWidth: CGFloat
}

struct ArrowAnnotation: Identifiable {
    let id = UUID()
    var start: NormalizedPoint
    var end: NormalizedPoint
    var color: RGBAColor
    var normalizedLineWidth: CGFloat
}

enum Annotation: Identifiable {
    case stroke(StrokeAnnotation)
    case rectangle(RectangleAnnotation)
    case circle(CircleAnnotation)
    case arrow(ArrowAnnotation)

    var id: UUID {
        switch self {
        case .stroke(let stroke):
            return stroke.id
        case .rectangle(let rectangle):
            return rectangle.id
        case .circle(let circle):
            return circle.id
        case .arrow(let arrow):
            return arrow.id
        }
    }
}

enum MarkupTool: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case circle
    case arrow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen:
            return "Pen"
        case .rectangle:
            return "Rectangle"
        case .circle:
            return "Circle"
        case .arrow:
            return "Arrow"
        }
    }

    var symbolName: String {
        switch self {
        case .pen:
            return "pencil.tip"
        case .rectangle:
            return "rectangle"
        case .circle:
            return "circle"
        case .arrow:
            return "arrow.up.right"
        }
    }
}
