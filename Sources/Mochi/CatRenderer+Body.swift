import CoreGraphics
import Foundation

extension CatRenderer {
    func draw(_ ctx: CGContext, pose: Pose) {
        if pose.shadow > 0.01 {
            let w: CGFloat = pose.view == .side ? 46 : 40
            ctx.setFillColor(rgb(0x000000, 0.14 * min(1.2, pose.shadow)))
            ctx.fillEllipse(in: CGRect(x: -w / 2, y: -3, width: w, height: 6.5))
        }
        ctx.saveGState()
        ctx.scaleBy(x: pose.squashX, y: pose.squashY)
        ctx.rotate(by: pose.rotation)
        if pose.purr > 0.01 {
            ctx.translateBy(x: sin(time * 97) * 0.35 * pose.purr, y: 0)
        }
        switch pose.view {
        case .side: drawSide(ctx, pose)
        case .front: drawFront(ctx, pose)
        }
        ctx.restoreGState()
    }

    // MARK: Side view

    private func bodyPoint(_ pose: Pose, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let c = cos(pose.bodyAngle), s = sin(pose.bodyAngle)
        return CGPoint(x: pose.body.x + x * c - y * s, y: pose.body.y + x * s + y * c)
    }

    private func drawLeg(_ ctx: CGContext, hip: CGPoint, foot: CGPoint, width: CGFloat, far: Bool) {
        let end = CGPoint(x: foot.x, y: foot.y + 3.5)
        limb(ctx, hip, end, width, far ? (coat.points ?? coat.shade) : (coat.points ?? coat.base))
        drawPaw(ctx, at: CGPoint(x: foot.x + 1.4, y: foot.y + 3.2), w: 11.5, h: 7, far: far)
    }

    private func drawPaw(_ ctx: CGContext, at c: CGPoint, w: CGFloat, h: CGFloat, far: Bool, toes: Bool = false) {
        let color: CGColor = far ? (coat.socks.map { $0.copy(alpha: 1)! } ?? coat.points ?? coat.shade) : pawColor
        fill(ctx, ellipse(c, w, h), color)
        if toes {
            ctx.setStrokeColor(coat.outline.copy(alpha: 0.7)!)
            ctx.setLineWidth(0.9)
            for dx: CGFloat in [-w * 0.17, w * 0.17] {
                ctx.move(to: CGPoint(x: c.x + dx, y: c.y + h * 0.5))
                ctx.addLine(to: CGPoint(x: c.x + dx, y: c.y + h * 0.05))
            }
            ctx.strokePath()
        }
    }

    private func drawSide(_ ctx: CGContext, _ pose: Pose) {
        let w = pose.bodyW, h = pose.bodyH
        let hipF = bodyPoint(pose, w * 0.27, -h * 0.12)
        let hipB = bodyPoint(pose, -w * 0.28, -h * 0.12)
        let tailBase = bodyPoint(pose, -w * 0.44, h * 0.08)
        let legs = pose.tuck < 0.5
        let pawUp = pose.footFN.y > hipF.y - 2

        if legs {
            drawLeg(ctx, hip: CGPoint(x: hipF.x + 2.5, y: hipF.y + 1), foot: pose.footFF, width: 9.5, far: true)
            drawLeg(ctx, hip: CGPoint(x: hipB.x + 2.5, y: hipB.y + 1), foot: pose.footBF, width: 10.5, far: true)
        }
        if !pose.tailFront { drawTail(ctx, base: tailBase, pose: pose) }
        if legs {
            if !pawUp { drawLeg(ctx, hip: hipF, foot: pose.footFN, width: 9.5, far: false) }
            if pose.haunch < 0.4 { drawLeg(ctx, hip: hipB, foot: pose.footBN, width: 10.5, far: false) }
        }

        // Body
        ctx.saveGState()
        ctx.translateBy(x: pose.body.x, y: pose.body.y)
        ctx.rotate(by: pose.bodyAngle)
        let shape = ellipse(.zero, w, h)
        fill(ctx, shape, coat.base, outline: false)
        decorate(ctx, shape) {
            if let a = coat.patchA {
                ctx.setFillColor(a)
                ctx.fillEllipse(in: CGRect(x: -w * 0.5, y: -h * 0.25, width: w * 0.5, height: h * 0.9))
            }
            if let b = coat.patchB {
                ctx.setFillColor(b)
                ctx.fillEllipse(in: CGRect(x: w * 0.05, y: h * 0.1, width: w * 0.3, height: h * 0.5))
            }
            if let belly = coat.belly {
                ctx.setFillColor(belly)
                ctx.fillEllipse(in: CGRect(x: -w * 0.3, y: -h * 0.8, width: w * 0.75, height: h * 0.6))
            }
            if let st = coat.stripes {
                ctx.setStrokeColor(st)
                ctx.setLineWidth(3)
                ctx.setLineCap(.round)
                for f: CGFloat in [-0.3, -0.12, 0.06] {
                    ctx.move(to: CGPoint(x: w * f, y: h * 0.55))
                    ctx.addQuadCurve(to: CGPoint(x: w * f - 2, y: h * 0.12), control: CGPoint(x: w * f + 1.5, y: h * 0.3))
                }
                ctx.strokePath()
            }
            if let pts = coat.points {
                ctx.setFillColor(pts.copy(alpha: 0.35)!)
                ctx.fillEllipse(in: CGRect(x: -w * 0.7, y: -h * 0.6, width: w * 0.4, height: h * 1.2))
            }
        }
        ctx.addPath(shape)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(lw)
        ctx.strokePath()
        ctx.restoreGState()

        // Sitting thigh + hind paw in front of it
        if pose.haunch > 0.05 {
            let r = 11.5 * pose.haunch
            let hc = CGPoint(x: pose.body.x - 4, y: r)
            fill(ctx, ellipse(hc, r * 2.1, r * 2), coat.base)
            if pose.haunch > 0.4 {
                drawPaw(ctx, at: CGPoint(x: pose.footBN.x + 3, y: pose.footBN.y + 3.2), w: 12, h: 7, far: false)
            }
        }
        if !legs {
            // Loaf: only the tips of the front paws peek out.
            drawPaw(ctx, at: CGPoint(x: pose.footFN.x + 1, y: pose.footFN.y + 2.6), w: 10, h: 6, far: false)
        }
        if pose.tailFront { drawTail(ctx, base: tailBase, pose: pose) }
        drawHead(ctx, at: pose.head, pose: pose)
        if legs && pawUp {
            // A raised paw (grooming) goes in front of the face.
            drawLeg(ctx, hip: hipF, foot: pose.footFN, width: 9.5, far: false)
        }
    }

    // MARK: Front view

    private func drawFront(_ ctx: CGContext, _ pose: Pose) {
        let b = pose.fBody, w = pose.fBodyW, h = pose.fBodyH
        let sitting = pose.fHaunch > 0.5
        let tailBase = CGPoint(x: b.x + w * 0.2, y: b.y - h * 0.34)
        if !pose.tailFront { drawTail(ctx, base: tailBase, pose: pose, length: 34) }

        if !sitting {
            for (s, foot) in [(-1 as CGFloat, pose.footL), (1, pose.footR)] {
                let hip = CGPoint(x: b.x + s * w * 0.26, y: b.y - h * 0.2)
                limb(ctx, hip, CGPoint(x: foot.x, y: foot.y + 2), 10, coat.points ?? coat.base)
                drawPaw(ctx, at: CGPoint(x: foot.x, y: foot.y + 1), w: 10, h: 8, far: false, toes: true)
            }
        }

        let shape = ellipse(b, w, h)
        fill(ctx, shape, coat.base, outline: false)
        decorate(ctx, shape) {
            if let a = coat.patchA {
                ctx.setFillColor(a)
                ctx.fillEllipse(in: CGRect(x: b.x - w * 0.62, y: b.y - h * 0.1, width: w * 0.55, height: h * 0.7))
            }
            if let pb = coat.patchB {
                ctx.setFillColor(pb)
                ctx.fillEllipse(in: CGRect(x: b.x + w * 0.2, y: b.y - h * 0.45, width: w * 0.4, height: h * 0.45))
            }
            if let chest = coat.belly ?? coat.muzzle, !pose.back {
                ctx.setFillColor(chest)
                ctx.fillEllipse(in: CGRect(x: b.x - w * 0.28, y: b.y - h * 0.32, width: w * 0.56, height: h * 0.7))
            }
            if let st = coat.stripes {
                ctx.setStrokeColor(st)
                ctx.setLineWidth(2.6)
                ctx.setLineCap(.round)
                if pose.back {
                    for dy: CGFloat in [0.3, 0.08, -0.14] {
                        ctx.move(to: CGPoint(x: b.x - w * 0.3, y: b.y + h * dy))
                        ctx.addQuadCurve(to: CGPoint(x: b.x + w * 0.3, y: b.y + h * dy), control: CGPoint(x: b.x, y: b.y + h * dy - 4))
                    }
                } else {
                    for s: CGFloat in [-1, 1] {
                        for dy: CGFloat in [0.12, -0.12] {
                            ctx.move(to: CGPoint(x: b.x + s * w * 0.52, y: b.y + h * dy))
                            ctx.addLine(to: CGPoint(x: b.x + s * w * 0.34, y: b.y + h * dy - 1))
                        }
                    }
                }
                ctx.strokePath()
            }
        }
        ctx.addPath(shape)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(lw)
        ctx.strokePath()

        if sitting {
            for s: CGFloat in [-1, 1] {
                let r = 10.5 * pose.fHaunch
                fill(ctx, ellipse(CGPoint(x: b.x + s * w * 0.36, y: b.y - h * 0.26), r * 2, r * 2), coat.base)
            }
            for foot in [pose.footL, pose.footR] where !pose.back {
                drawPaw(ctx, at: CGPoint(x: foot.x, y: foot.y + 3), w: 12, h: 7.5, far: false, toes: true)
            }
        }

        func arms() {
            for (s, paw) in [(-1 as CGFloat, pose.pawL), (1, pose.pawR)] {
                let shoulder = CGPoint(x: b.x + s * w * 0.21, y: b.y + pose.shoulderY)
                limb(ctx, shoulder, CGPoint(x: paw.x, y: paw.y + 2), 9, coat.points ?? coat.base)
                drawPaw(ctx, at: CGPoint(x: paw.x, y: paw.y + 2.6), w: 10.5, h: 7.5, far: false,
                        toes: pose.grip > 0.5 || sitting)
            }
        }
        if !pose.pawsFront && !pose.back { arms() }
        drawHead(ctx, at: pose.fHead, pose: pose)
        if pose.pawsFront {
            arms()
        } else if pose.grip > 0.5 {
            // Hanging on: the gripping paws curl over the edge in front of everything.
            for paw in [pose.pawL, pose.pawR] {
                drawPaw(ctx, at: CGPoint(x: paw.x, y: paw.y + 2.6), w: 11, h: 7.5, far: false, toes: true)
            }
        }
        if pose.tailFront { drawTail(ctx, base: tailBase, pose: pose, length: 34) }
    }
}

// MARK: - Cartoon scuffle

extension CatRenderer {
    /// Two cats wrestling: a bouncing dust cloud with paws, tails and stars flying out.
    func drawFightCloud(_ ctx: CGContext, other: Coat) {
        let t = time
        let c = CGPoint(x: 0, y: 30 + sin(t * 15) * 2)
        for i in 0..<7 {
            let fi = CGFloat(i)
            let a = fi * 0.9 + t * (i % 2 == 0 ? 3.1 : -2.6) + sin(t * 7 + fi) * 0.4
            let coatI = i % 2 == 0 ? coat : other
            let r1: CGFloat = 36 + 6 * sin(t * 11 + fi * 2)
            let a0 = CGPoint(x: c.x + cos(a) * 16, y: c.y + sin(a) * 13)
            let a1 = CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1 * 0.8)
            let r = CatRenderer(coat: coatI, time: t)
            if i == 3 || i == 6 {
                var tp = Pose()
                tp.tailAngle = a; tp.tailCurl = 0.6 * sin(t * 9 + fi); tp.tailSway = 0.3; tp.tailSwaySpeed = 12
                r.drawTail(ctx, base: a0, pose: tp, length: 30)
            } else {
                r.limb(ctx, a0, a1, 8, coatI.points ?? coatI.base)
                r.fill(ctx, r.ellipse(a1, 10, 8), r.pawColor)
            }
        }
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-20, 26, 16), (0, 38, 20), (19, 28, 17), (-8, 16, 15),
                                                    (12, 14, 14), (-27, 38, 11), (26, 41, 12), (2, 24, 18)]
        for (i, (x, y, r)) in puffs.enumerated() {
            let fi = CGFloat(i)
            let rr = r + 1.5 * sin(t * 17 + fi * 1.7)
            let pc = CGPoint(x: c.x + x + 2 * sin(t * 13 + fi), y: c.y - 30 + y + 2 * cos(t * 11 + fi))
            fill(ctx, ellipse(pc, rr * 2, rr * 1.8), rgb(0xF6F2EA))
        }
        ctx.setFillColor(rgb(0xF6F2EA))
        for (x, y, r) in puffs { ctx.fillEllipse(in: CGRect(x: c.x + x - r + 3, y: c.y - 30 + y - r * 0.9 + 3, width: r * 2 - 6, height: r * 1.8 - 6)) }
        // Squinty faces in the dust.
        for (dx, s) in [(-11 as CGFloat, 1 as CGFloat), (12, -1)] {
            for e: CGFloat in [-3.2, 3.2] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: c.x + dx + e - 1.6 * s, y: c.y + 2.5))
                p.addLine(to: CGPoint(x: c.x + dx + e + 1.6 * s, y: c.y + 1))
                p.addLine(to: CGPoint(x: c.x + dx + e - 1.6 * s, y: c.y - 0.5))
                stroke(ctx, p, CatRenderer.eyeDark, 1.3)
            }
        }
        // Stars orbiting the scuffle.
        for i in 0..<3 {
            let a = t * 4 + CGFloat(i) * 2.1
            let sc = CGPoint(x: c.x + cos(a) * 34, y: c.y + 26 + sin(a) * 10)
            let star = CGMutablePath()
            for k in 0..<10 {
                let rr: CGFloat = k % 2 == 0 ? 5 : 2.2
                let aa = CGFloat(k) * .pi / 5 + t * 3
                let pt = CGPoint(x: sc.x + cos(aa) * rr, y: sc.y + sin(aa) * rr)
                k == 0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.closeSubpath()
            ctx.addPath(star)
            ctx.setFillColor(rgb(0xFFD54F))
            ctx.setStrokeColor(rgb(0xC48A1C))
            ctx.setLineWidth(0.8)
            ctx.drawPath(using: .fillStroke)
        }
    }
}
