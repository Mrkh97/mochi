import Foundation

/// x' = a·x + c·y + tx, y' = b·x + d·y + ty, as in CoreGraphics.
struct CGAffineTransform {
    var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    /// This transform followed by `t`.
    func concatenating(_ t: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: a * t.a + b * t.c, b: a * t.b + b * t.d,
                          c: c * t.a + d * t.c, d: c * t.b + d * t.d,
                          tx: tx * t.a + ty * t.c + t.tx, ty: tx * t.b + ty * t.d + t.ty)
    }

    func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return CGAffineTransform(a: d / det, b: -b / det, c: -c / det, d: a / det,
                                 tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

/// A path as CoreGraphics builds one: the same elements, in the same order and direction,
/// so shapes overlap and fill exactly as they do on macOS.
struct PathData {
    enum Element {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, CGPoint)
        case cubic(CGPoint, CGPoint, CGPoint)
        case close
    }

    private(set) var elements: [Element] = []
    /// Applied to every point as it's added (the context's CTM; identity for a CGPath).
    var transform = CGAffineTransform.identity
    /// The current point and subpath start, before `transform`.
    private var current: CGPoint?
    private var start: CGPoint?

    var isEmpty: Bool { elements.isEmpty }

    mutating func removeAll() {
        elements.removeAll(keepingCapacity: true)
        current = nil
        start = nil
    }

    mutating func move(to p: CGPoint) {
        elements.append(.move(transform.apply(p)))
        start = p
        current = p
    }

    mutating func addLine(to p: CGPoint) {
        guard current != nil else { return move(to: p) }
        elements.append(.line(transform.apply(p)))
        current = p
    }

    mutating func addQuadCurve(to p: CGPoint, control: CGPoint) {
        if current == nil { move(to: control) }
        elements.append(.quad(transform.apply(control), transform.apply(p)))
        current = p
    }

    mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) {
        if current == nil { move(to: control1) }
        elements.append(.cubic(transform.apply(control1), transform.apply(control2), transform.apply(p)))
        current = p
    }

    mutating func closeSubpath() {
        guard current != nil else { return }
        elements.append(.close)
        current = start
    }

    mutating func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for p in points.dropFirst() { addLine(to: p) }
    }

    /// Quarter circles (or less), starting at `startAngle`; a line joins it to the current point.
    mutating func addArc(center: CGPoint, radius r: CGFloat, startAngle s: CGFloat, endAngle e: CGFloat, clockwise: Bool) {
        let twoPi = 2 * CGFloat.pi
        // Going the "wrong" way round to the end angle means going nearly all the way round.
        var sweep = e - s
        if clockwise && sweep > 0 {
            sweep = -(twoPi - sweep.truncatingRemainder(dividingBy: twoPi))
        } else if !clockwise && sweep < 0 {
            sweep = twoPi - (-sweep).truncatingRemainder(dividingBy: twoPi)
        }
        let p0 = CGPoint(x: center.x + r * cos(s), y: center.y + r * sin(s))
        if current == nil { move(to: p0) } else { addLine(to: p0) }
        var a0 = s
        var left = sweep
        while abs(left) > 1e-9 {
            let step = left > 0 ? min(left, .pi / 2) : max(left, -.pi / 2)
            let a1 = a0 + step
            let k = 4 / 3 * tan(step / 4) * r
            let from = CGPoint(x: center.x + r * cos(a0), y: center.y + r * sin(a0))
            let to = CGPoint(x: center.x + r * cos(a1), y: center.y + r * sin(a1))
            addCurve(to: to,
                     control1: CGPoint(x: from.x - k * sin(a0), y: from.y + k * cos(a0)),
                     control2: CGPoint(x: to.x + k * sin(a1), y: to.y - k * cos(a1)))
            a0 = a1
            left -= step
        }
    }

    /// Four curves counter-clockwise (y up) from the middle of the right edge, then closed.
    mutating func addEllipse(in r: CGRect) {
        let k: CGFloat = 0.5522847498
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        move(to: CGPoint(x: r.maxX, y: cy))
        addCurve(to: CGPoint(x: cx, y: r.maxY), control1: CGPoint(x: r.maxX, y: cy + ry * k), control2: CGPoint(x: cx + rx * k, y: r.maxY))
        addCurve(to: CGPoint(x: r.minX, y: cy), control1: CGPoint(x: cx - rx * k, y: r.maxY), control2: CGPoint(x: r.minX, y: cy + ry * k))
        addCurve(to: CGPoint(x: cx, y: r.minY), control1: CGPoint(x: r.minX, y: cy - ry * k), control2: CGPoint(x: cx - rx * k, y: r.minY))
        addCurve(to: CGPoint(x: r.maxX, y: cy), control1: CGPoint(x: cx + rx * k, y: r.minY), control2: CGPoint(x: r.maxX, y: cy - ry * k))
        closeSubpath()
    }

    mutating func addRect(_ r: CGRect) {
        move(to: CGPoint(x: r.minX, y: r.minY))
        addLine(to: CGPoint(x: r.maxX, y: r.minY))
        addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        addLine(to: CGPoint(x: r.minX, y: r.maxY))
        closeSubpath()
    }

    /// Counter-clockwise (y up) from the middle of the right edge, like CoreGraphics.
    mutating func addRoundedRect(_ r: CGRect, cornerWidth cw: CGFloat, cornerHeight ch: CGFloat) {
        let k: CGFloat = 0.5522847498
        let cw = min(cw, r.width / 2), ch = min(ch, r.height / 2)
        move(to: CGPoint(x: r.maxX, y: r.midY))
        addLine(to: CGPoint(x: r.maxX, y: r.maxY - ch))
        addCurve(to: CGPoint(x: r.maxX - cw, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - ch + ch * k), control2: CGPoint(x: r.maxX - cw + cw * k, y: r.maxY))
        addLine(to: CGPoint(x: r.minX + cw, y: r.maxY))
        addCurve(to: CGPoint(x: r.minX, y: r.maxY - ch), control1: CGPoint(x: r.minX + cw - cw * k, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - ch + ch * k))
        addLine(to: CGPoint(x: r.minX, y: r.minY + ch))
        addCurve(to: CGPoint(x: r.minX + cw, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + ch - ch * k), control2: CGPoint(x: r.minX + cw - cw * k, y: r.minY))
        addLine(to: CGPoint(x: r.maxX - cw, y: r.minY))
        addCurve(to: CGPoint(x: r.maxX, y: r.minY + ch), control1: CGPoint(x: r.maxX - cw + cw * k, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + ch - ch * k))
        closeSubpath()
    }

    /// Appends another path's elements, passed through `transform`.
    mutating func append(_ other: PathData) {
        for e in other.elements {
            switch e {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quad(let c, let p): addQuadCurve(to: p, control: c)
            case .cubic(let c1, let c2, let p): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }

    /// The elements with every point passed through `t`.
    func elements(applying t: CGAffineTransform) -> [Element] {
        elements.map { e in
            switch e {
            case .move(let p): return .move(t.apply(p))
            case .line(let p): return .line(t.apply(p))
            case .quad(let c, let p): return .quad(t.apply(c), t.apply(p))
            case .cubic(let c1, let c2, let p): return .cubic(t.apply(c1), t.apply(c2), t.apply(p))
            case .close: return .close
            }
        }
    }
}
