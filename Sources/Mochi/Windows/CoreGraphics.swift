import CDirect2D
import Foundation

// Windows has no CoreGraphics. This is the part of it Mochi draws with, implemented on Direct2D,
// so the drawing code is the same on both platforms. Coordinates, path construction, fill rules and
// the graphics-state stack behave as CoreGraphics' do.

typealias CGWindowID = UInt32

struct CGColor {
    let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat

    init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func copy(alpha: CGFloat) -> CGColor? {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

class CGPath {
    fileprivate(set) var data = PathData()

    init() {}

    convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        if let t = transform { data.transform = t.pointee }
        data.addEllipse(in: rect)
    }

    convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        if let t = transform { data.transform = t.pointee }
        data.addRoundedRect(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }
}

final class CGMutablePath: CGPath {
    func move(to p: CGPoint) { data.move(to: p) }
    func addLine(to p: CGPoint) { data.addLine(to: p) }
    func addLines(between points: [CGPoint]) { data.addLines(between: points) }
    func addQuadCurve(to p: CGPoint, control: CGPoint) { data.addQuadCurve(to: p, control: control) }
    func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) { data.addCurve(to: p, control1: control1, control2: control2) }
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        data.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }
    func addEllipse(in rect: CGRect) { data.addEllipse(in: rect) }
    func addRect(_ rect: CGRect) { data.addRect(rect) }
    func addPath(_ path: CGPath) { data.append(path.data) }
    func closeSubpath() { data.closeSubpath() }
}

enum CGLineCap: Int32 { case butt, round, square }
enum CGLineJoin: Int32 { case miter, round, bevel }
enum CGPathDrawingMode { case fill, eoFill, stroke, fillStroke, eoFillStroke }

/// Draws into a Direct2D canvas. Like a CoreGraphics bitmap context, the origin starts at the
/// bottom-left with y pointing up, and points added to the current path are fixed in pixels
/// by the transform in effect when they're added.
final class CGContext {
    private struct State {
        var ctm: CGAffineTransform
        var fill = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        var stroke = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        var lineWidth: CGFloat = 1
        var lineCap = CGLineCap.butt
        var lineJoin = CGLineJoin.miter
        var alpha: CGFloat = 1
        /// Clips pushed since this state was saved.
        var clips = 0
    }

    let canvas: OpaquePointer
    let width: Int
    let height: Int
    private var state: State
    private var saved: [State] = []
    /// The current path, in pixels.
    private var path = PathData()

    init(canvas: OpaquePointer, width: Int, height: Int) {
        self.canvas = canvas
        self.width = width
        self.height = height
        state = State(ctm: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height)))
        path.transform = state.ctm
    }

    var ctm: CGAffineTransform { state.ctm }

    // MARK: Graphics state

    func saveGState() {
        saved.append(state)
        state.clips = 0
    }

    func restoreGState() {
        guard let s = saved.popLast() else { return }
        for _ in 0..<state.clips { mg_pop_clip(canvas) }
        state = s
        path.transform = state.ctm
    }

    private func concatenate(_ t: CGAffineTransform) {
        state.ctm = t.concatenating(state.ctm)
        path.transform = state.ctm
    }

    func translateBy(x: CGFloat, y: CGFloat) { concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)) }
    func scaleBy(x: CGFloat, y: CGFloat) { concatenate(CGAffineTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)) }
    func rotate(by angle: CGFloat) {
        concatenate(CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0))
    }

    func setFillColor(_ c: CGColor) { state.fill = c }
    func setStrokeColor(_ c: CGColor) { state.stroke = c }
    func setLineWidth(_ w: CGFloat) { state.lineWidth = w }
    func setLineCap(_ cap: CGLineCap) { state.lineCap = cap }
    func setLineJoin(_ join: CGLineJoin) { state.lineJoin = join }
    func setAlpha(_ a: CGFloat) { state.alpha = a }

    // MARK: Current path

    func beginPath() { path.removeAll() }
    func move(to p: CGPoint) { path.move(to: p) }
    func addLine(to p: CGPoint) { path.addLine(to: p) }
    func addLines(between points: [CGPoint]) { path.addLines(between: points) }
    func addQuadCurve(to p: CGPoint, control: CGPoint) { path.addQuadCurve(to: p, control: control) }
    func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) { path.addCurve(to: p, control1: control1, control2: control2) }
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }
    func addEllipse(in rect: CGRect) { path.addEllipse(in: rect) }
    func addRect(_ rect: CGRect) { path.addRect(rect) }
    func addPath(_ p: CGPath) { path.append(p.data) }
    func closePath() { path.closeSubpath() }

    // MARK: Painting

    func fillPath() {
        fill(path.elements)
        path.removeAll()
    }

    func strokePath() {
        stroke(path.elements)
        path.removeAll()
    }

    func drawPath(using mode: CGPathDrawingMode) {
        switch mode {
        case .fill, .eoFill: fill(path.elements)
        case .stroke: stroke(path.elements)
        case .fillStroke, .eoFillStroke:
            fill(path.elements)
            stroke(path.elements)
        }
        path.removeAll()
    }

    // Rectangles and ellipses go straight to Direct2D's own shapes: much cheaper than a path.

    func fill(_ rect: CGRect) {
        mg_fill_rect(canvas, Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height), Self.mg(state.ctm), mgColor(state.fill))
        path.removeAll()
    }

    func fillEllipse(in rect: CGRect) {
        mg_fill_ellipse(canvas, Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height), Self.mg(state.ctm), mgColor(state.fill))
        path.removeAll()
    }

    func clip() {
        Self.withPath(path.elements) { mg_push_clip(canvas, $0) }
        state.clips += 1
        path.removeAll()
    }

    func clip(to rect: CGRect) {
        var r = PathData()
        r.transform = state.ctm
        r.addRect(rect)
        Self.withPath(r.elements) { mg_push_clip(canvas, $0) }
        state.clips += 1
    }

    /// Heavy letters with a white outline, centred on the origin.
    func drawLetters(_ text: String, size: CGFloat, color: CGColor, outline: CGFloat) {
        let units = Array(text.utf16)
        units.withUnsafeBufferPointer { u in
            mg_text(canvas, u.baseAddress, Int32(u.count), Float(size), Self.mg(state.ctm), mgColor(color), Float(outline))
        }
    }

    private func mgColor(_ c: CGColor) -> MGColor {
        MGColor(r: Float(c.red), g: Float(c.green), b: Float(c.blue), a: Float(c.alpha * state.alpha))
    }

    private func fill(_ elements: [PathData.Element]) {
        guard !elements.isEmpty else { return }
        let color = mgColor(state.fill)
        Self.withPath(elements) { mg_fill(canvas, $0, color) }
    }

    /// The pen is shaped by the transform in effect now, so the pixel path goes back to user space
    /// and Direct2D strokes it through the transform.
    private func stroke(_ elements: [PathData.Element]) {
        guard !elements.isEmpty else { return }
        let toUser = state.ctm.inverted()
        let user = elements.map { e -> PathData.Element in
            switch e {
            case .move(let p): return .move(toUser.apply(p))
            case .line(let p): return .line(toUser.apply(p))
            case .quad(let c, let p): return .quad(toUser.apply(c), toUser.apply(p))
            case .cubic(let c1, let c2, let p): return .cubic(toUser.apply(c1), toUser.apply(c2), toUser.apply(p))
            case .close: return .close
            }
        }
        let color = mgColor(state.stroke)
        let m = Self.mg(state.ctm)
        let width = Float(state.lineWidth), cap = state.lineCap.rawValue, join = state.lineJoin.rawValue
        Self.withPath(user) { mg_stroke(canvas, $0, m, width, cap, join, color) }
    }

    private static func mg(_ t: CGAffineTransform) -> MGTransform {
        MGTransform(a: Float(t.a), b: Float(t.b), c: Float(t.c), d: Float(t.d), tx: Float(t.tx), ty: Float(t.ty))
    }

    private static func withPath(_ elements: [PathData.Element], _ body: (MGPath) -> Void) {
        var ops: [UInt8] = []
        var points: [Float] = []
        ops.reserveCapacity(elements.count)
        points.reserveCapacity(elements.count * 6)
        func add(_ p: CGPoint) { points.append(Float(p.x)); points.append(Float(p.y)) }
        for e in elements {
            switch e {
            case .move(let p): ops.append(UInt8(MG_MOVE)); add(p)
            case .line(let p): ops.append(UInt8(MG_LINE)); add(p)
            case .quad(let c, let p): ops.append(UInt8(MG_QUAD)); add(c); add(p)
            case .cubic(let c1, let c2, let p): ops.append(UInt8(MG_CUBIC)); add(c1); add(c2); add(p)
            case .close: ops.append(UInt8(MG_CLOSE))
            }
        }
        ops.withUnsafeBufferPointer { o in
            points.withUnsafeBufferPointer { p in
                body(MGPath(ops: o.baseAddress, count: Int32(o.count), points: p.baseAddress))
            }
        }
    }
}
