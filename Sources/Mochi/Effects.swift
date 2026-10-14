import Foundation

enum FXKind { case heart, z, sweat, exclaim, dust, note, sparkle, anger, word, crumb, drop }

struct Particle {
    var kind: FXKind
    var p: CGPoint          // cat-local, y up, not mirrored
    var v: CGPoint
    var age: CGFloat = 0
    var life: CGFloat
    var size: CGFloat
    var seed: CGFloat = .random(in: 0...6.28)
    var text: String = ""
    var color: Ink = .systemBrown
}

/// Little floating bits of emotion around a cat.
final class Effects {
    private(set) var items: [Particle] = []

    func spawn(_ kind: FXKind, at p: CGPoint, v: CGPoint = .zero, life: CGFloat = 1.6, size: CGFloat = 1) {
        if items.count > 40 { items.removeFirst() }
        items.append(Particle(kind: kind, p: p, v: v, life: life, size: size))
    }

    /// A little word bubble ("MEOW!", "hss!", "nom").
    func say(_ text: String, at p: CGPoint, color: Ink, life: CGFloat = 1.3) {
        spawn(.word, at: p, v: CGPoint(x: .random(in: -6...6), y: 22), life: life)
        items[items.count - 1].text = text
        items[items.count - 1].color = color
    }

    func hearts(at p: CGPoint, count: Int = 3) {
        for i in 0..<count {
            spawn(.heart, at: CGPoint(x: p.x + .random(in: -10...10), y: p.y + CGFloat(i) * 4),
                  v: CGPoint(x: .random(in: -14...14), y: .random(in: 26...40)), life: .random(in: 1.3...1.9),
                  size: .random(in: 0.8...1.15))
        }
    }

    func dust(at p: CGPoint, strength: CGFloat = 1) {
        for s: CGFloat in [-1, 1] {
            for _ in 0..<2 {
                spawn(.dust, at: CGPoint(x: p.x + s * .random(in: 8...16), y: p.y + 2),
                      v: CGPoint(x: s * .random(in: 18...40) * strength, y: .random(in: 4...14)),
                      life: .random(in: 0.35...0.55), size: .random(in: 0.7...1.1) * strength)
            }
        }
    }

    func update(_ dt: CGFloat) {
        for i in items.indices {
            items[i].age += dt
            items[i].p.x += items[i].v.x * dt
            items[i].p.y += items[i].v.y * dt
            switch items[i].kind {
            case .heart, .note, .z:
                items[i].p.x += sin(items[i].age * 4 + items[i].seed) * 10 * dt
            case .sweat:
                items[i].v.y -= 60 * dt
            case .crumb, .drop:
                items[i].v.y -= 420 * dt
            case .dust:
                items[i].v.x *= 1 - 3 * dt
            default: break
            }
        }
        items.removeAll { $0.age >= $0.life }
    }

    func draw(_ ctx: CGContext) {
        for it in items {
            let t = it.age / it.life
            let alpha = min(1, (1 - t) * 2.5) * min(1, it.age * 8)
            let pop = it.kind == .exclaim ? 1 + 0.4 * max(0, 1 - it.age * 6) : min(1, 0.4 + it.age * 5)
            ctx.saveGState()
            ctx.translateBy(x: it.p.x, y: it.p.y)
            ctx.scaleBy(x: it.size * pop, y: it.size * pop)
            ctx.setAlpha(alpha)
            switch it.kind {
            case .heart: drawHeart(ctx)
            case .z: platform.drawText(t < 0.5 ? "z" : "Z", size: 11 + t * 6, ink: .srgb(0.45, 0.56, 0.82), in: ctx)
            case .note: platform.drawText("♪", size: 13, ink: .srgb(0.85, 0.45, 0.7), in: ctx)
            case .exclaim: platform.drawText("!", size: 17, ink: .srgb(0.95, 0.35, 0.35), in: ctx)
            case .sweat: drawSweat(ctx)
            case .dust:
                ctx.setFillColor(rgb(0xE6DFD5, 0.9))
                let r = 3 + t * 5
                ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            case .sparkle: drawSparkle(ctx)
            case .anger: drawAnger(ctx)
            case .word: platform.drawText(it.text, size: 12, ink: it.color, in: ctx)
            case .crumb:
                ctx.setFillColor(rgb(0x9A5B2E))
                ctx.fillEllipse(in: CGRect(x: -1.6, y: -1.3, width: 3.2, height: 2.6))
            case .drop:
                ctx.setFillColor(rgb(0x6EC6F5))
                ctx.fillEllipse(in: CGRect(x: -1.4, y: -1.4, width: 2.8, height: 2.8))
            }
            ctx.restoreGState()
        }
    }

    private func drawHeart(_ ctx: CGContext) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -6))
        p.addCurve(to: CGPoint(x: -7, y: 2), control1: CGPoint(x: -3, y: -3.5), control2: CGPoint(x: -7, y: -1.5))
        p.addCurve(to: CGPoint(x: 0, y: 3.2), control1: CGPoint(x: -7, y: 6.5), control2: CGPoint(x: -1.2, y: 7))
        p.addCurve(to: CGPoint(x: 7, y: 2), control1: CGPoint(x: 1.2, y: 7), control2: CGPoint(x: 7, y: 6.5))
        p.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: 7, y: -1.5), control2: CGPoint(x: 3, y: -3.5))
        ctx.addPath(p)
        ctx.setFillColor(rgb(0xFF6F93))
        ctx.setStrokeColor(rgb(0xFFFFFF))
        ctx.setLineWidth(1.4)
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(rgb(0xFFFFFF, 0.8))
        ctx.fillEllipse(in: CGRect(x: -5, y: 1.5, width: 2.6, height: 2.2))
    }

    private func drawSweat(_ ctx: CGContext) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 6))
        p.addQuadCurve(to: CGPoint(x: 3.4, y: -1.5), control: CGPoint(x: 3.2, y: 2))
        p.addArc(center: CGPoint(x: 0, y: -1.5), radius: 3.4, startAngle: 0, endAngle: .pi, clockwise: true)
        p.addQuadCurve(to: CGPoint(x: 0, y: 6), control: CGPoint(x: -3.2, y: 2))
        ctx.addPath(p)
        ctx.setFillColor(rgb(0x9FDBFF))
        ctx.setStrokeColor(rgb(0x4A8DC2))
        ctx.setLineWidth(1)
        ctx.drawPath(using: .fillStroke)
    }

    /// The classic cartoon anger vein.
    private func drawAnger(_ ctx: CGContext) {
        ctx.setStrokeColor(rgb(0xE53935))
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        for k in 0..<4 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(k) * .pi / 2)
            ctx.move(to: CGPoint(x: 1.6, y: 6.5))
            ctx.addQuadCurve(to: CGPoint(x: 6.5, y: 1.6), control: CGPoint(x: 1.8, y: 1.8))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private func drawSparkle(_ ctx: CGContext) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 6))
        p.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 1, y: 1))
        p.addQuadCurve(to: CGPoint(x: 0, y: -6), control: CGPoint(x: 1, y: -1))
        p.addQuadCurve(to: CGPoint(x: -6, y: 0), control: CGPoint(x: -1, y: -1))
        p.addQuadCurve(to: CGPoint(x: 0, y: 6), control: CGPoint(x: -1, y: 1))
        ctx.addPath(p)
        ctx.setFillColor(rgb(0xFFD95A))
        ctx.fillPath()
    }
}
