import AppKit

/// A view that renders on the CPU into its own bitmap and hands the layer a finished image
/// (letting AppKit draw directly made macOS reserve hundreds of MB of GPU buffers).
/// An offscreen bitmap in the window's own colour space. Drawing in sRGB on a P3 display made
/// Core Animation convert every pixel of every frame on the CPU, which was most of our CPU time.
func displayBitmap(reuse old: CGContext?, width w: Int, height h: Int, window: NSWindow?) -> CGContext? {
    let space = window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    if let old, old.width == w, old.height == h, old.colorSpace == space { return old }
    return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
}

class BitmapView: NSView {
    // Two bitmaps used alternately, so drawing a frame never forces a copy of the one on screen.
    private var bitmaps: [CGContext?] = [nil, nil]
    private var current = 0
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Draw in view points, y up.
    func render(_ ctx: CGContext) {}

    override func updateLayer() {
        guard let layer else { return }
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return }
        current ^= 1
        bitmaps[current] = displayBitmap(reuse: bitmaps[current], width: w, height: h, window: window)
        guard let ctx = bitmaps[current] else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        render(ctx)
        ctx.restoreGState()
        layer.contentsScale = scale
        layer.contents = ctx.makeImage()
    }
}

/// Food and water. Cats get hungry and thirsty; you keep these topped up.
final class Bowls {
    static let viewSize = CGSize(width: 160, height: 66)
    static let matTop: CGFloat = 16
    static let foodX: CGFloat = 50
    static let waterX: CGFloat = 112

    let panel: CatPanel
    private let view: BowlsView
    private(set) var scale: CGFloat
    private(set) var originCG: CGPoint
    var floating = true { didSet { applyLevel() } }
    private(set) var food: CGFloat
    private(set) var water: CGFloat
    var onChanged: (() -> Void)?
    private var press: CGPoint?
    private var dragOffset: CGPoint?
    private var dragged = false
    private(set) var refillT: [CGFloat] = [-1, -1]   // food, water
    private(set) var time: CGFloat = 0
    private let defaults = UserDefaults.standard

    init(scale: CGFloat, defaultBottomRight: CGPoint) {
        self.scale = scale
        food = CGFloat(defaults.object(forKey: "food") as? Double ?? 1)
        water = CGFloat(defaults.object(forKey: "water") as? Double ?? 1)
        let size = CGSize(width: Bowls.viewSize.width * scale, height: Bowls.viewSize.height * scale)
        if let a = defaults.array(forKey: "bowlsOrigin") as? [Double], a.count == 2,
           World.shared.screens.contains(where: { $0.frame.contains(CGPoint(x: a[0] + size.width / 2, y: a[1] + size.height / 2)) }) {
            originCG = CGPoint(x: a[0], y: a[1])
        } else {
            originCG = CGPoint(x: defaultBottomRight.x - size.width, y: defaultBottomRight.y - size.height)
        }
        panel = CatPanel(size: size)
        view = BowlsView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        view.bowls = self
        applyLevel()
        place()
    }

    var frameCG: CGRect {
        CGRect(origin: originCG, size: CGSize(width: Bowls.viewSize.width * scale, height: Bowls.viewSize.height * scale))
    }
    var level: NSWindow.Level { floating ? .floating : .desktopCat }

    private func local(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: originCG.x + x * scale, y: originCG.y + (Bowls.viewSize.height - y) * scale)
    }

    var surface: Surface {
        let top = local(0, Bowls.matTop).y
        return Surface(ref: .bowls, y: top, minX: local(12, 0).x, maxX: local(148, 0).x,
                       z: floating ? World.topZ - 1 : -0.5)
    }

    /// Where a cat stands to eat (or drink), approaching from `side` (-1 left, +1 right).
    func spot(drink: Bool, side: CGFloat) -> CGFloat {
        let bx = local(drink ? Bowls.waterX : Bowls.foodX, 0).x
        return bx + side * 27 * scale
    }

    func amount(drink: Bool) -> CGFloat { drink ? water : food }

    /// A cat takes a mouthful. Returns how much it actually got.
    @discardableResult
    func consume(_ amount: CGFloat, drink: Bool) -> CGFloat {
        let have = self.amount(drink: drink)
        let got = min(have, amount)
        if drink { water = max(0, water - got) } else { food = max(0, food - got) }
        save()
        return got
    }

    func refill(drink: Bool) {
        if drink { water = 1 } else { food = 1 }
        refillT[drink ? 1 : 0] = 0
        save()
    }

    private func save() {
        defaults.set(Double(food), forKey: "food")
        defaults.set(Double(water), forKey: "water")
        onChanged?()
        view.needsDisplay = true
    }

    func update(_ dt: CGFloat) {
        time += dt
        var animating = false
        for i in 0..<2 where refillT[i] >= 0 {
            refillT[i] += dt
            if refillT[i] > 0.9 { refillT[i] = -1 }
            animating = true
        }
        // Redraw while something moves: a refill pour, or the bobbing "!" over an empty bowl.
        if animating || food < 0.03 || water < 0.03 { view.needsDisplay = true }
    }

    func setScale(_ s: CGFloat) {
        let bottomLeft = CGPoint(x: frameCG.minX, y: frameCG.maxY)
        scale = s
        let size = CGSize(width: Bowls.viewSize.width * s, height: Bowls.viewSize.height * s)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        originCG = CGPoint(x: bottomLeft.x, y: bottomLeft.y - size.height)
        place()
    }

    func move(to origin: CGPoint) {
        originCG = origin
        place()
        defaults.set([Double(originCG.x), Double(originCG.y)], forKey: "bowlsOrigin")
    }

    func place() {
        panel.setFrameOrigin(Coords.cocoa(fromCG: frameCG).origin)
        World.shared.bowlsSurface = surface
        view.needsDisplay = true
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    private func applyLevel() {
        panel.level = level
        if panel.isVisible { panel.orderFrontRegardless() }
        World.shared.bowlsSurface = surface
    }

    // MARK: Mouse: click a bowl to refill it, drag to move the whole set.

    /// Which bowl (if any) is under a global point: false = food, true = water.
    func bowl(at m: CGPoint) -> Bool? {
        for (x, drink) in [(Bowls.foodX, false), (Bowls.waterX, true)] {
            let a = local(x - 23, 38), b = local(x + 23, 12)
            if CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).contains(m) { return drink }
        }
        return nil
    }

    var hitRect: CGRect {
        let a = local(4, 40), b = local(156, 3)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    func updateMouse(_ m: CGPoint) {
        let over = hitRect.contains(m) || press != nil
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    func mouseDown() {
        let m = Coords.mouse
        press = m
        dragged = false
        dragOffset = CGPoint(x: m.x - originCG.x, y: m.y - originCG.y)
    }

    func mouseDragged() {
        guard let p = press, let o = dragOffset else { return }
        let m = Coords.mouse
        if !dragged && hypot(m.x - p.x, m.y - p.y) > 3 { dragged = true }
        if dragged { move(to: CGPoint(x: m.x - o.x, y: m.y - o.y)) }
    }

    func mouseUp() {
        if !dragged, let p = press {
            if let drink = bowl(at: p) { refill(drink: drink) } else { refill(drink: false); refill(drink: true) }
        }
        press = nil
        dragOffset = nil
    }
}

final class BowlsView: BitmapView {
    weak var bowls: Bowls?

    override func mouseDown(with event: NSEvent) { bowls?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { bowls?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { bowls?.mouseUp() }

    private static let line = rgb(0x6B4A3A)

    override func render(_ ctx: CGContext) {
        guard let b = bowls else { return }
        Self.paint(ctx, scale: b.scale, food: b.food, water: b.water, refillT: b.refillT, time: b.time)
    }

    /// Draw in view points, y up. Also paints the README pictures.
    static func paint(_ ctx: CGContext, scale: CGFloat, food: CGFloat, water: CGFloat, refillT: [CGFloat] = [-1, -1], time: CGFloat = 0) {
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        // Placemat
        let mat = CGPath(roundedRect: CGRect(x: 6, y: 4, width: 148, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(mat)
        ctx.setFillColor(rgb(0xF7D3DD))
        ctx.setStrokeColor(rgb(0xB9808F))
        ctx.setLineWidth(1.5)
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(rgb(0xE9A9BA))
        for x: CGFloat in [16, 144] {
            ctx.fillEllipse(in: CGRect(x: x - 3, y: 7.5, width: 6, height: 4.5))
            for dx: CGFloat in [-3.5, 0, 3.5] { ctx.fillEllipse(in: CGRect(x: x + dx - 1.2, y: 12.3, width: 2.4, height: 2.2)) }
        }
        drawBowl(ctx, x: Bowls.foodX, body: rgb(0xFF8F80), rim: rgb(0xFFB3A8), inside: rgb(0xD9675A), level: food, drink: false, refill: refillT[0], time: time)
        drawBowl(ctx, x: Bowls.waterX, body: rgb(0x7FB8F0), rim: rgb(0xB0D6FA), inside: rgb(0x5E93CC), level: water, drink: true, refill: refillT[1], time: time)
    }

    private static func drawBowl(_ ctx: CGContext, x cx: CGFloat, body: CGColor, rim: CGColor, inside: CGColor,
                                 level: CGFloat, drink: Bool, refill rt: CGFloat, time: CGFloat) {
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(line)
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: cx - 21, y: 31))
        shape.addLine(to: CGPoint(x: cx - 16, y: 17))
        shape.addQuadCurve(to: CGPoint(x: cx + 16, y: 17), control: CGPoint(x: cx, y: 12.5))
        shape.addLine(to: CGPoint(x: cx + 21, y: 31))
        shape.closeSubpath()
        ctx.addPath(shape)
        ctx.setFillColor(body)
        ctx.drawPath(using: .fillStroke)
        // Icon on the front: a fish for food, a droplet for water.
        ctx.setFillColor(rgb(0xFFFFFF, 0.9))
        if drink {
            let d = CGMutablePath()
            d.move(to: CGPoint(x: cx, y: 28))
            d.addQuadCurve(to: CGPoint(x: cx + 3.6, y: 21), control: CGPoint(x: cx + 3.6, y: 24.5))
            d.addArc(center: CGPoint(x: cx, y: 21), radius: 3.6, startAngle: 0, endAngle: .pi, clockwise: true)
            d.addQuadCurve(to: CGPoint(x: cx, y: 28), control: CGPoint(x: cx - 3.6, y: 24.5))
            ctx.addPath(d); ctx.fillPath()
        } else {
            ctx.fillEllipse(in: CGRect(x: cx - 6, y: 20, width: 9, height: 5.5))
            ctx.move(to: CGPoint(x: cx + 2, y: 22.75))
            ctx.addLine(to: CGPoint(x: cx + 6.5, y: 25.5))
            ctx.addLine(to: CGPoint(x: cx + 6.5, y: 20))
            ctx.closePath(); ctx.fillPath()
        }
        ctx.addEllipse(in: CGRect(x: cx - 21, y: 26, width: 42, height: 10))
        ctx.setFillColor(rim)
        ctx.drawPath(using: .fillStroke)
        let inner = CGRect(x: cx - 17, y: 28.2, width: 34, height: 6.4)
        ctx.setFillColor(inside)
        ctx.fillEllipse(in: inner)

        if level > 0.02 {
            if drink {
                let k = 0.6 + 0.4 * level
                let wr = CGRect(x: cx - 17 * k, y: 31.4 - 3.2 * k, width: 34 * k, height: 6.4 * k)
                ctx.setFillColor(rgb(0x68C3F4))
                ctx.fillEllipse(in: wr)
                ctx.setFillColor(rgb(0xFFFFFF, 0.75))
                ctx.fillEllipse(in: CGRect(x: cx - 8 * k, y: 32, width: 6 * k, height: 1.6))
            } else {
                // A mound of kibble that shrinks as it's eaten.
                let h = 2 + 7 * level
                ctx.saveGState()
                let mound = CGMutablePath()
                mound.addEllipse(in: inner)
                mound.addEllipse(in: CGRect(x: cx - 15.5, y: 31.4 - h * 0.4, width: 31, height: h * 1.6))
                ctx.addPath(mound)
                ctx.setFillColor(rgb(0xB8692F))
                ctx.fillPath()
                let count = Int(5 + 12 * level)
                for i in 0..<count {
                    let fi = CGFloat(i)
                    let px = cx + sin(fi * 2.4) * (12 - fi * 0.3)
                    let py = 31.2 + abs(cos(fi * 1.7)) * h * 0.75
                    ctx.setFillColor(i % 2 == 0 ? rgb(0x9C5424) : rgb(0xD08A48))
                    ctx.fillEllipse(in: CGRect(x: px - 2, y: py - 1.4, width: 4, height: 2.8))
                }
                ctx.restoreGState()
            }
        }
        ctx.addEllipse(in: CGRect(x: cx - 21, y: 26, width: 42, height: 10))
        ctx.setStrokeColor(line)
        ctx.strokePath()

        // Refill pour.
        if rt >= 0 {
            for i in 0..<6 {
                let fi = CGFloat(i)
                let y = 64 - (rt * 60 - fi * 6).truncatingRemainder(dividingBy: 34) - 2
                guard y > 31 else { continue }
                ctx.setFillColor(drink ? rgb(0x68C3F4) : rgb(0xB8692F))
                ctx.fillEllipse(in: CGRect(x: cx - 6 + fi * 2.4, y: y, width: 3.4, height: 3))
            }
        }
        // Empty: a bobbing "!" so you notice.
        if level < 0.03 {
            let by = 48 + 2.5 * sin(time * 5)
            ctx.addEllipse(in: CGRect(x: cx + 6, y: by - 7, width: 14, height: 14))
            ctx.setFillColor(rgb(0xFFFFFF))
            ctx.setStrokeColor(rgb(0xE53935))
            ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(rgb(0xE53935))
            ctx.fill(CGRect(x: cx + 12, y: by - 1.5, width: 2, height: 6))
            ctx.fillEllipse(in: CGRect(x: cx + 11.9, y: by - 4.6, width: 2.2, height: 2.2))
        }
    }
}
