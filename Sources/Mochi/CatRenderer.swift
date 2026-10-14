import CoreGraphics
import Foundation

/// Draws a cat from a `Pose` into a context already set up in cat-local space
/// (origin at the contact point, y up, cat facing +x).
struct CatRenderer {
    let coat: Coat
    let time: CGFloat
    let lw: CGFloat = 1.6
    static let eyeDark = rgb(0x2A1C17)

    // MARK: Primitives

    func ellipse(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), transform: nil)
    }

    func capsule(_ a: CGPoint, _ b: CGPoint, _ width: CGFloat) -> CGPath {
        let line = CGMutablePath()
        line.move(to: a)
        line.addLine(to: CGPoint(x: b.x + 0.001, y: b.y))
        return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
    }

    /// A round-ended limb with an outline, drawn as two stroked lines (much cheaper than outlining a path).
    func limb(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ color: CGColor) {
        ctx.setLineCap(.round)
        ctx.move(to: a); ctx.addLine(to: b)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(width + lw)
        ctx.strokePath()
        ctx.move(to: a); ctx.addLine(to: b)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width - lw)
        ctx.strokePath()
    }

    func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, outline: Bool = true) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        if outline {
            ctx.setStrokeColor(coat.outline)
            ctx.setLineWidth(lw)
            ctx.setLineJoin(.round)
            ctx.drawPath(using: .fillStroke)
        } else {
            ctx.fillPath()
        }
    }

    func stroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// Fills `decor` clipped to `shape`, then re-strokes the shape so the outline stays crisp.
    func decorate(_ ctx: CGContext, _ shape: CGPath, _ body: () -> Void) {
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        body()
        ctx.restoreGState()
    }

    var pawColor: CGColor { coat.socks ?? coat.points ?? coat.base }

    // MARK: Tail

    /// The tail's centre line, plus the last stretch of it (for a differently coloured tip).
    func tailPath(base: CGPoint, pose: Pose, length: CGFloat) -> CGPath { tailPaths(base: base, pose: pose, length: length).0 }

    func tailPaths(base: CGPoint, pose: Pose, length: CGFloat) -> (CGPath, CGPath) {
        let sway = sin(time * pose.tailSwaySpeed) * pose.tailSway
        let wave = sin(time * pose.tailSwaySpeed - 0.9) * pose.tailSway * 1.3
        let a0 = pose.tailAngle + sway
        let c = pose.tailCurl + wave
        let L = length * pose.tailLen
        func dir(_ a: CGFloat) -> CGPoint { CGPoint(x: cos(a), y: sin(a)) }
        let d0 = dir(a0), d1 = dir(a0 + c * 0.8), d2 = dir(a0 + c * 1.7)
        let p1 = CGPoint(x: base.x + d0.x * L * 0.42, y: base.y + d0.y * L * 0.42)
        let p2 = CGPoint(x: p1.x + d1.x * L * 0.36, y: p1.y + d1.y * L * 0.36)
        let p3 = CGPoint(x: p2.x + d2.x * L * 0.3, y: p2.y + d2.y * L * 0.3)
        let m12 = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let path = CGMutablePath()
        path.move(to: base)
        path.addQuadCurve(to: m12, control: p1)
        path.addQuadCurve(to: p3, control: p2)
        // Split the last curve in half: the tip is its second half.
        let half = CGPoint(x: 0.25 * m12.x + 0.5 * p2.x + 0.25 * p3.x, y: 0.25 * m12.y + 0.5 * p2.y + 0.25 * p3.y)
        let tip = CGMutablePath()
        tip.move(to: half)
        tip.addQuadCurve(to: p3, control: CGPoint(x: (p2.x + p3.x) / 2, y: (p2.y + p3.y) / 2))
        return (path, tip)
    }

    func drawTail(_ ctx: CGContext, base: CGPoint, pose: Pose, length: CGFloat = 36, width: CGFloat = 7.5) {
        let (center, tipPath) = tailPaths(base: base, pose: pose, length: length)
        let w = width + 7 * pose.puff
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(center)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(w + lw)
        ctx.strokePath()
        ctx.addPath(center)
        ctx.setStrokeColor(coat.points ?? coat.base)
        ctx.setLineWidth(w - lw)
        ctx.strokePath()
        if let tip = coat.tailTip ?? coat.patchB {
            ctx.addPath(tipPath)
            ctx.setStrokeColor(tip)
            ctx.setLineWidth(w - lw)
            ctx.strokePath()
        }
    }

    // MARK: Head

    func headShape(rx: CGFloat, ry: CGFloat) -> CGPath {
        // A soft "mochi" shape: rounder on top, wide fluffy cheeks.
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -rx, y: -1))
        p.addCurve(to: CGPoint(x: 0, y: ry), control1: CGPoint(x: -rx, y: ry * 0.6), control2: CGPoint(x: -rx * 0.58, y: ry))
        p.addCurve(to: CGPoint(x: rx, y: -1), control1: CGPoint(x: rx * 0.58, y: ry), control2: CGPoint(x: rx, y: ry * 0.6))
        p.addCurve(to: CGPoint(x: 0, y: -ry * 0.9), control1: CGPoint(x: rx * 1.02, y: -ry * 0.62), control2: CGPoint(x: rx * 0.74, y: -ry * 0.9))
        p.addCurve(to: CGPoint(x: -rx, y: -1), control1: CGPoint(x: -rx * 0.74, y: -ry * 0.9), control2: CGPoint(x: -rx * 1.02, y: -ry * 0.62))
        p.closeSubpath()
        return p
    }

    func drawEar(_ ctx: CGContext, rx: CGFloat, ry: CGFloat, angleDeg: CGFloat, size: CGFloat, pose: Pose, twitch: CGFloat) {
        let th = angleDeg * .pi / 180
        let baseC = CGPoint(x: rx * 0.86 * cos(th), y: ry * 0.86 * sin(th))
        let splay = (th - .pi / 2) * 0.55
        let flat = (1 - pose.earPerk) * (th > .pi / 2 ? 0.8 : -0.8)
        let dir = splay + flat + twitch
        ctx.saveGState()
        ctx.translateBy(x: baseC.x, y: baseC.y)
        ctx.rotate(by: dir)
        let h = 14.5 * size * (0.78 + 0.22 * pose.earPerk)
        let w = 8.2 * size
        func earPath(_ w: CGFloat, _ h: CGFloat, _ dy: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w, y: dy - 3))
            p.addQuadCurve(to: CGPoint(x: -1.3, y: dy + h - 1.2), control: CGPoint(x: -w * 0.62, y: dy + h * 0.6))
            p.addQuadCurve(to: CGPoint(x: 1.3, y: dy + h - 1.2), control: CGPoint(x: 0, y: dy + h + 0.9))
            p.addQuadCurve(to: CGPoint(x: w, y: dy - 3), control: CGPoint(x: w * 0.62, y: dy + h * 0.6))
            p.closeSubpath()
            return p
        }
        fill(ctx, earPath(w, h, 0), coat.points ?? coat.base)
        fill(ctx, earPath(w * 0.52, h * 0.62, 2.2), pose.back ? coat.shade : coat.innerEar, outline: false)
        ctx.restoreGState()
    }

    func drawHead(_ ctx: CGContext, at c: CGPoint, pose: Pose) {
        let rx: CGFloat = 17.5, ry: CGFloat = 15
        let turn = max(-1, min(1, pose.headTurn))
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: pose.headTilt)
        ctx.scaleBy(x: pose.headScale, y: pose.headScale)

        let shift = turn * 11
        let farR = turn > 0 ? 1 - 0.1 * turn : 1
        let farL = turn < 0 ? 1 + 0.1 * turn : 1
        drawEar(ctx, rx: rx, ry: ry, angleDeg: 124 - shift, size: farL, pose: pose,
                twitch: turn >= 0 ? pose.earTwitch * 0.5 : 0)
        drawEar(ctx, rx: rx, ry: ry, angleDeg: 56 - shift, size: farR, pose: pose,
                twitch: turn < 0 ? -pose.earTwitch * 0.5 : 0)

        let shape = headShape(rx: rx, ry: ry)
        fill(ctx, shape, coat.base, outline: false)
        let fx = turn * 5.5
        decorate(ctx, shape) {
            if let a = coat.patchA {
                ctx.setFillColor(a)
                ctx.fillEllipse(in: CGRect(x: -rx - 6, y: 1, width: 22, height: 22))
            }
            if let b = coat.patchB {
                ctx.setFillColor(b)
                ctx.fillEllipse(in: CGRect(x: 6, y: 5, width: 16, height: 14))
            }
            if let pts = coat.points {
                ctx.setFillColor(pts.copy(alpha: 0.85)!)
                ctx.fillEllipse(in: CGRect(x: fx - 10, y: -13, width: 20, height: 15))
            }
            if let st = coat.stripes, pose.eyes != .none {
                ctx.setStrokeColor(st)
                ctx.setLineWidth(2.4)
                ctx.setLineCap(.round)
                for dx: CGFloat in [-4.2, 0, 4.2] {
                    ctx.move(to: CGPoint(x: fx * 0.7 + dx, y: ry + 1))
                    ctx.addLine(to: CGPoint(x: fx * 0.7 + dx * 0.8, y: ry - 6.5 + abs(dx) * 0.4))
                }
                ctx.strokePath()
            }
            if let mz = coat.muzzle, pose.eyes != .none {
                ctx.setFillColor(mz)
                ctx.fillEllipse(in: CGRect(x: fx - 8, y: -ry * 0.92, width: 16, height: 11))
            }
        }
        ctx.addPath(shape)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(lw)
        ctx.strokePath()

        if pose.eyes != .none { drawFace(ctx, fx: fx, turn: turn, pose: pose) }
        ctx.restoreGState()
    }

    func drawFace(_ ctx: CGContext, fx: CGFloat, turn: CGFloat, pose: Pose) {
        // Blush first so the eyes sit on top.
        if pose.blush > 0.01 {
            ctx.setFillColor(coat.blush.copy(alpha: min(0.6, pose.blush * 0.55))!)
            for s: CGFloat in [-1, 1] {
                let squeeze = 1 - 0.25 * max(0, -s * turn)
                ctx.fillEllipse(in: CGRect(x: fx + s * 11.2 - 3.4 * squeeze, y: -8.1, width: 6.8 * squeeze, height: 3.8))
            }
        }
        // Whiskers
        ctx.setStrokeColor((coat.faceLine ?? coat.outline).copy(alpha: 0.5)!)
        ctx.setLineWidth(0.8)
        for s: CGFloat in [-1, 1] {
            let x0 = fx + s * 12.5
            ctx.move(to: CGPoint(x: x0, y: -4.2)); ctx.addLine(to: CGPoint(x: x0 + s * 8, y: -3))
            ctx.move(to: CGPoint(x: x0, y: -6.3)); ctx.addLine(to: CGPoint(x: x0 + s * 8, y: -7.6))
        }
        ctx.strokePath()

        for s: CGFloat in [-1, 1] {
            let far = s * turn > 0 ? 1 - 0.1 * abs(turn) : 1
            let ex = fx + s * 7.3 * (1 - 0.06 * abs(turn))
            drawEye(ctx, CGPoint(x: ex, y: -1.4), scale: far, side: s, pose: pose)
        }

        if pose.brow > 0.05 {
            // Furrowed brows: the inner ends dip toward the nose.
            for s: CGFloat in [-1, 1] {
                let ex = fx + s * 7.3 * (1 - 0.06 * abs(turn))
                let b = CGMutablePath()
                b.move(to: CGPoint(x: ex + s * 4.3, y: 6.4))
                b.addLine(to: CGPoint(x: ex - s * 2.9, y: 6.4 - 3.4 * pose.brow))
                stroke(ctx, b, (coat.faceLine ?? CatRenderer.eyeDark).copy(alpha: min(1, pose.brow * 1.4))!, 1.8)
            }
        }

        // Nose
        let nose = CGMutablePath()
        let nx = fx + turn * 0.4
        nose.move(to: CGPoint(x: nx - 2, y: -4.4))
        nose.addQuadCurve(to: CGPoint(x: nx + 2, y: -4.4), control: CGPoint(x: nx, y: -3.6))
        nose.addQuadCurve(to: CGPoint(x: nx, y: -6.1), control: CGPoint(x: nx + 1.4, y: -5.4))
        nose.addQuadCurve(to: CGPoint(x: nx - 2, y: -4.4), control: CGPoint(x: nx - 1.4, y: -5.4))
        ctx.addPath(nose)
        ctx.setFillColor(coat.nose)
        ctx.fillPath()

        // Mouth
        if pose.mouthOpen > 0.12 {
            let w = 4.6 + pose.mouthOpen * 3, h = 2.6 + pose.mouthOpen * 6
            let r = CGRect(x: nx - w / 2, y: -6.8 - h, width: w, height: h)
            let m = CGPath(roundedRect: r, cornerWidth: w * 0.45, cornerHeight: h * 0.45, transform: nil)
            fill(ctx, m, rgb(0x8A3443))
            ctx.saveGState()
            ctx.addPath(m); ctx.clip()
            ctx.setFillColor(rgb(0xFF8DA1))
            ctx.fillEllipse(in: CGRect(x: nx - w * 0.38, y: r.minY - 1, width: w * 0.76, height: h * 0.55))
            ctx.restoreGState()
            if pose.brow > 0.4 {
                ctx.setFillColor(rgb(0xFFFFFF))
                for fx2 in [nx - w * 0.26, nx + w * 0.26] {
                    ctx.move(to: CGPoint(x: fx2 - 1.1, y: r.maxY - 0.4))
                    ctx.addLine(to: CGPoint(x: fx2 + 1.1, y: r.maxY - 0.4))
                    ctx.addLine(to: CGPoint(x: fx2, y: r.maxY - 2.8))
                    ctx.closePath()
                }
                ctx.fillPath()
            }
        } else {
            if pose.tongue > 0.08 {
                let th = 2.2 + pose.tongue * 2.6
                let t = CGPath(roundedRect: CGRect(x: nx - 1.8, y: -7.6 - th, width: 3.6, height: th + 1.5),
                               cornerWidth: 1.7, cornerHeight: 1.7, transform: nil)
                fill(ctx, t, rgb(0xFF8DA1))
            }
            let m = CGMutablePath()
            m.move(to: CGPoint(x: nx, y: -6))
            m.addLine(to: CGPoint(x: nx, y: -6.6))
            if pose.frown > 0.5 {
                // Grumpy: a little upside-down curve.
                m.move(to: CGPoint(x: nx - 3.3, y: -9.2))
                m.addQuadCurve(to: CGPoint(x: nx + 3.3, y: -9.2), control: CGPoint(x: nx, y: -6.2))
            } else {
                m.move(to: CGPoint(x: nx - 3.4, y: -6.4))
                m.addQuadCurve(to: CGPoint(x: nx, y: -6.6), control: CGPoint(x: nx - 1.7, y: -9.4))
                m.addQuadCurve(to: CGPoint(x: nx + 3.4, y: -6.4), control: CGPoint(x: nx + 1.7, y: -9.4))
            }
            stroke(ctx, m, coat.faceLine ?? coat.outline, 1.15)
        }
    }

    func drawEye(_ ctx: CGContext, _ c: CGPoint, scale: CGFloat, side: CGFloat, pose: Pose) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: scale, y: scale)
        let dark = CatRenderer.eyeDark
        var style = pose.eyes
        if style == .open && pose.eyeOpen < 0.2 { style = .sleep }
        switch style {
        case .open:
            let open = min(1.15, pose.eyeOpen)
            let lx = pose.lookX * 1.3, ly = pose.lookY * 1.1
            let rx: CGFloat = 3.6, ry: CGFloat = 4.4 * open
            let eye = ellipse(CGPoint(x: lx, y: ly), rx * 2, ry * 2)
            if let iris = coat.iris {
                fill(ctx, eye, iris, outline: false)
                ctx.addPath(eye); ctx.setStrokeColor(dark); ctx.setLineWidth(0.9); ctx.strokePath()
                ctx.setFillColor(dark)
                ctx.fillEllipse(in: CGRect(x: lx - rx * 0.5, y: ly - ry * 0.82, width: rx, height: ry * 1.64))
            } else {
                fill(ctx, eye, dark, outline: false)
            }
            ctx.addPath(eye); ctx.clip()
            ctx.setFillColor(rgb(0xFFFFFF))
            ctx.fillEllipse(in: CGRect(x: lx + 0.1, y: ly + ry * 0.3 - 0.4, width: 2.7, height: 2.7))
            ctx.setFillColor(rgb(0xFFFFFF, 0.8))
            ctx.fillEllipse(in: CGRect(x: lx - 2, y: ly - ry * 0.55 - 0.3, width: 1.3, height: 1.3))
        case .happy:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -3.3, y: -1.2))
            p.addQuadCurve(to: CGPoint(x: 3.3, y: -1.2), control: CGPoint(x: 0, y: 4.2))
            stroke(ctx, p, dark, 1.6)
        case .sleep:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -3.4, y: 0.4))
            p.addQuadCurve(to: CGPoint(x: 3.4, y: 0.4), control: CGPoint(x: 0, y: -3.4))
            stroke(ctx, p, dark, 1.5)
        case .wide:
            let eye = ellipse(.zero, 8.6, 9.6)
            fill(ctx, eye, rgb(0xFFFFFF))
            ctx.setFillColor(dark)
            let lx = pose.lookX * 1.5, ly = pose.lookY * 1.5
            ctx.fillEllipse(in: CGRect(x: lx - 1.9, y: ly - 1.9, width: 3.8, height: 3.8))
        case .struggle:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 2.6 * side, y: 2.8))
            p.addLine(to: CGPoint(x: -2.6 * side, y: 0))
            p.addLine(to: CGPoint(x: 2.6 * side, y: -2.8))
            stroke(ctx, p, dark, 1.6)
        case .none:
            break
        }
        ctx.restoreGState()
    }
}
