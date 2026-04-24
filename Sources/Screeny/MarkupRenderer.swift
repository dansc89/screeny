import AppKit

struct MarkupRenderer {
    static func render(baseImage: NSImage, annotations: [Annotation]) -> NSImage? {
        guard let sourceCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = sourceCGImage.width
        let height = sourceCGImage.height

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .high

        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let maxDimension = max(CGFloat(width), CGFloat(height))

        for annotation in annotations {
            switch annotation {
            case .stroke(let stroke):
                drawStroke(stroke, in: context, width: CGFloat(width), height: CGFloat(height), maxDimension: maxDimension)
            case .rectangle(let rectangle):
                drawRectangle(rectangle, in: context, width: CGFloat(width), height: CGFloat(height), maxDimension: maxDimension)
            case .circle(let circle):
                drawCircle(circle, in: context, width: CGFloat(width), height: CGFloat(height), maxDimension: maxDimension)
            case .arrow(let arrow):
                drawArrow(arrow, in: context, width: CGFloat(width), height: CGFloat(height), maxDimension: maxDimension)
            }
        }

        guard let rendered = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: rendered, size: NSSize(width: width, height: height))
    }

    private static func drawStroke(_ stroke: StrokeAnnotation, in context: CGContext, width: CGFloat, height: CGFloat, maxDimension: CGFloat) {
        guard stroke.points.count > 1 else {
            return
        }

        context.saveGState()
        context.setStrokeColor(stroke.color.nsColor.cgColor)
        context.setLineWidth(max(1, stroke.normalizedLineWidth * maxDimension))
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let first = denormalized(stroke.points[0], width: width, height: height)
        context.beginPath()
        context.move(to: first)
        for point in stroke.points.dropFirst() {
            context.addLine(to: denormalized(point, width: width, height: height))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawRectangle(_ rectangle: RectangleAnnotation, in context: CGContext, width: CGFloat, height: CGFloat, maxDimension: CGFloat) {
        let start = denormalized(rectangle.start, width: width, height: height)
        let end = denormalized(rectangle.end, width: width, height: height)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )

        context.saveGState()
        context.setStrokeColor(rectangle.color.nsColor.cgColor)
        context.setLineWidth(max(1, rectangle.normalizedLineWidth * maxDimension))
        context.stroke(rect)
        context.restoreGState()
    }

    private static func drawArrow(_ arrow: ArrowAnnotation, in context: CGContext, width: CGFloat, height: CGFloat, maxDimension: CGFloat) {
        let start = denormalized(arrow.start, width: width, height: height)
        let end = denormalized(arrow.end, width: width, height: height)
        let lineWidth = max(1, arrow.normalizedLineWidth * maxDimension)

        context.saveGState()
        context.setStrokeColor(arrow.color.nsColor.cgColor)
        context.setFillColor(arrow.color.nsColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(14, lineWidth * 3)
        let headAngle: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.beginPath()
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private static func drawCircle(_ circle: CircleAnnotation, in context: CGContext, width: CGFloat, height: CGFloat, maxDimension: CGFloat) {
        let start = denormalized(circle.start, width: width, height: height)
        let end = denormalized(circle.end, width: width, height: height)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )

        context.saveGState()
        context.setStrokeColor(circle.color.nsColor.cgColor)
        context.setLineWidth(max(1, circle.normalizedLineWidth * maxDimension))
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    private static func denormalized(_ point: NormalizedPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x * width, y: (1 - point.y) * height)
    }
}
