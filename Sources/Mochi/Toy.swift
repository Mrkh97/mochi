import Foundation

/// A yarn ball. Drag it around and the cats go wild; let go and it bounces and rolls.
final class Toy {
    enum State { case flying, rolling, resting, held, caught }

    let sprite: Sprite
    private let view: ToyView
    private(set) var scale: CGFloat
    private(set) var p = CGPoint.zero          // centre of the ball, CG coords
    private(set) var v = CGPoint.zero
    private(set) var state: State = .flying
    private(set) weak var holder: Cat?
    private(set) var surface: SurfaceRef?
    private(set) var spin: CGFloat = 0
    private(set) var time: CGFloat = 0
    private(set) var visible = false
    private(set) var restingFor: CGFloat = 0
    private var grab: CGPoint?
    private let g: CGFloat = 2400
    static let viewSide: CGFloat = 84

    init(scale: CGFloat) {
        self.scale = scale
        sprite = platform.makeSprite(size: CGSize(width: Toy.viewSide * scale, height: Toy.viewSide * scale))
        sprite.level = .toy
        view = ToyView()
        sprite.content = view
        view.toy = self
    }

    var r: CGFloat { 9 * scale }
    var speed: CGFloat { hypot(v.x, v.y) }
    var isFree: Bool { state != .held && state != .caught }
    var world: World { World.shared }

    func setScale(_ s: CGFloat) {
        scale = s
        sprite.size = CGSize(width: Toy.viewSide * s, height: Toy.viewSide * s)
    }

    func show(at point: CGPoint) {
        p = point
        v = CGPoint(x: .random(in: -60...60), y: -120)
        state = .flying
        surface = nil
        visible = true
        place()
        sprite.orderFront()
    }

    func hide() {
        visible = false
        holder = nil
        state = .flying
        sprite.orderOut()
    }

    // MARK: Cats

    func caught(by cat: Cat) {
        state = .caught
        holder = cat
        grab = nil
        surface = nil
    }

    /// While caught, the cat moves the ball around with its paws.
    func hold(at point: CGPoint) {
        let dt: CGFloat = 1 / 60
        v = CGPoint(x: (point.x - p.x) / dt * 0.2, y: (point.y - p.y) / dt * 0.2)
        p = point
    }

    func release(v: CGPoint) {
        guard state == .caught else { return }
        holder = nil
        state = .flying
        self.v = v
    }

    /// Give it a shove (used by the test mode to play fetch with itself).
    func toss(_ v: CGPoint) {
        guard isFree else { return }
        state = .flying
        surface = nil
        self.v = v
    }

    // MARK: Physics

    func update(_ dt: CGFloat) {
        guard visible else { return }
        time += dt
        let before = p
        switch state {
        case .held:
            if let gr = grab {
                let m = Coords.mouse
                let np = CGPoint(x: m.x - gr.x, y: m.y - gr.y)
                let nv = CGPoint(x: (np.x - p.x) / max(dt, 0.001), y: (np.y - p.y) / max(dt, 0.001))
                v = CGPoint(x: v.x + (nv.x - v.x) * 0.35, y: v.y + (nv.y - v.y) * 0.35)
                p = np
            }
        case .caught:
            if let h = holder, h.carryingToy {
                // Still airborne after the catch: the ball travels in its paws.
                if !(h.action is PlayWithToy) { p = h.pawWorld }
            } else {
                holder = nil
                state = .flying
                v = CGPoint(x: 0, y: -150)
            }
        case .flying:
            fly(dt)
        case .rolling, .resting:
            roll(dt)
        }
        if state == .resting { restingFor += dt } else { restingFor = 0 }
        spin += (p.x - before.x) / r
        place()
        updateMouse()
        // A ball lying still doesn't need redrawing (the strand settles within half a second).
        if state != .resting || restingFor < 0.5 { sprite.setNeedsDisplay() }
    }

    private func fly(_ dt: CGFloat) {
        v.y = min(2200, v.y + g * dt)
        v.x *= 1 - 0.3 * dt
        let si = world.screenIndex(at: p)
        guard si < world.screens.count else { return }
        let vis = world.screens[si].visible, fr = world.screens[si].frame
        var x = p.x + v.x * dt
        // It sails across to a display next door; other edges bounce it back.
        if x < vis.minX + r && !world.onAnyScreen(CGPoint(x: fr.minX - 2, y: p.y)) { x = vis.minX + r; v.x = abs(v.x) * 0.6 }
        if x > vis.maxX - r && !world.onAnyScreen(CGPoint(x: fr.maxX + 2, y: p.y)) { x = vis.maxX - r; v.x = -abs(v.x) * 0.6 }
        let y0 = p.y, y1 = p.y + v.y * dt
        let floor = world.surface(.floor(si))
        let floorHit = floor.flatMap { f in y1 + r >= f.y ? f : nil }
        if v.y > 0, let s = world.landing(x: x, fromY: min(y0 + r, floor?.y ?? y0 + r), toY: max(y1 + r, y0 + r + 0.5),
                                          z: World.topZ, screen: si) ?? floorHit {
            p = CGPoint(x: x, y: s.y - r)
            if v.y > 260 {
                v.y = -v.y * 0.42
                v.x *= 0.8
            } else {
                v.y = 0
                surface = s.ref
                state = .rolling
            }
            return
        }
        if y1 < vis.minY + r && !world.onAnyScreen(CGPoint(x: x, y: fr.minY - 2)) { v.y = abs(v.y) * 0.3 }
        p = CGPoint(x: x, y: min(y1, vis.maxY + 200))
    }

    private func roll(_ dt: CGFloat) {
        guard let ref = surface, let s = world.surface(ref) else { state = .flying; return }
        p.y = s.y - r
        v.x *= exp(-1.4 * dt)
        p.x += v.x * dt
        if p.x < s.minX - 16 || p.x > s.maxX + 16 {
            // Rolled off the edge.
            state = .flying
            surface = nil
            return
        }
        let si = world.screenIndex(at: p)
        let vis = world.screens[si].visible, fr = world.screens[si].frame
        if p.x < vis.minX + r && !world.onAnyScreen(CGPoint(x: fr.minX - 2, y: p.y)) { p.x = vis.minX + r; v.x = abs(v.x) * 0.5 }
        if p.x > vis.maxX - r && !world.onAnyScreen(CGPoint(x: fr.maxX + 2, y: p.y)) { p.x = vis.maxX - r; v.x = -abs(v.x) * 0.5 }
        state = abs(v.x) < 6 ? .resting : .rolling
        if state == .resting { v.x = 0 }
    }

    private func place() {
        let side = Toy.viewSide * scale
        let o = CGPoint(x: ((p.x - side / 2) * 2).rounded() / 2,
                        y: ((p.y + side / 2) * 2).rounded() / 2 - side)
        if sprite.origin != o { sprite.origin = o }
    }

    // MARK: Mouse

    private func updateMouse() {
        let m = Coords.mouse
        let over = hypot(m.x - p.x, m.y - p.y) < r + 8 * scale || state == .held
        if sprite.clickThrough == over { sprite.clickThrough = !over }
    }

    func mouseDown() {
        let m = Coords.mouse
        if state == .caught, let cat = holder {
            // Snatched back from a playing cat.
            cat.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
        }
        holder = nil
        grab = CGPoint(x: m.x - p.x, y: m.y - p.y)
        state = .held
        surface = nil
        v = .zero
    }

    func mouseUp() {
        guard state == .held else { return }
        grab = nil
        state = .flying
        v = CGPoint(x: max(-1400, min(1400, v.x * 0.8)), y: max(-1400, min(1000, v.y * 0.8)))
    }
}

final class ToyView: SpriteContent {
    weak var toy: Toy?

    func mouseDown() { toy?.mouseDown() }
    func mouseUp() { toy?.mouseUp() }

    func draw(_ ctx: CGContext) {
        guard let toy else { return }
        Self.paint(ctx, scale: toy.scale, v: toy.v, time: toy.time, spin: toy.spin,
                   grounded: toy.state == .resting || toy.state == .rolling)
    }

    /// Draw in view points, y up. Also paints the README pictures.
    static func paint(_ ctx: CGContext, scale s: CGFloat, v: CGPoint, time: CGFloat, spin: CGFloat, grounded: Bool) {
        ctx.scaleBy(x: s, y: s)
        let c = CGPoint(x: Toy.viewSide / 2, y: Toy.viewSide / 2)
        let r: CGFloat = 9
        let outline = rgb(0xA8456A)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // The loose end of yarn trails behind the ball, or lies on the ground when it's still.
        let vx = v.x / s, vy = -v.y / s
        let sp = hypot(vx, vy)
        let away = sp > 30 ? CGPoint(x: -vx / sp, y: -vy / sp) : CGPoint(x: -0.75, y: -0.66)
        let start = CGPoint(x: c.x + away.x * r * 0.9, y: c.y + away.y * r * 0.9)
        let len: CGFloat = 16 + min(14, sp / 60)
        let wig = sin(time * 12) * (sp > 30 ? 5 : 1.5)
        let mid = CGPoint(x: start.x + away.x * len * 0.5 - away.y * wig, y: start.y + away.y * len * 0.5 + away.x * wig)
        let end = CGPoint(x: start.x + away.x * len + away.y * wig * 0.6, y: start.y + away.y * len - away.x * wig * 0.6)
        let strand = CGMutablePath()
        strand.move(to: start)
        strand.addQuadCurve(to: end, control: mid)
        ctx.addPath(strand)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(3.4)
        ctx.strokePath()
        ctx.addPath(strand)
        ctx.setStrokeColor(rgb(0xFF9DBB))
        ctx.setLineWidth(1.8)
        ctx.strokePath()

        // Shadow when it's on something.
        if grounded {
            ctx.setFillColor(rgb(0x000000, 0.13))
            ctx.fillEllipse(in: CGRect(x: c.x - 9, y: c.y - r - 2, width: 18, height: 4))
        }

        let ball = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(rgb(0xFF8FB1))
        ctx.fillEllipse(in: ball)
        ctx.saveGState()
        ctx.addEllipse(in: ball)
        ctx.clip()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: -spin)
        // Wound strands of yarn.
        ctx.setStrokeColor(rgb(0xE8648E))
        ctx.setLineWidth(1.3)
        for k in 0..<4 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(k) * .pi / 4)
            ctx.addEllipse(in: CGRect(x: -r * 1.1, y: -r * 0.42, width: r * 2.2, height: r * 0.84))
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.setStrokeColor(rgb(0xFFC2D5))
        ctx.setLineWidth(1)
        ctx.addArc(center: .zero, radius: r * 0.55, startAngle: 0.3, endAngle: 2.4, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.setFillColor(rgb(0xFFFFFF, 0.55))
        ctx.fillEllipse(in: CGRect(x: c.x - 5.5, y: c.y + 2.5, width: 4, height: 3))
        ctx.addEllipse(in: ball)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(1.6)
        ctx.strokePath()
    }
}
