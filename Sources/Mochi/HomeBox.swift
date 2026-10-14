import AppKit

/// The cat's home: a cardboard box you can drag anywhere. It's made of two windows
/// (back wall and front wall) so a cat can sit *inside* it, sandwiched between them.
final class HomeBox {
    static let viewSize = CGSize(width: 130, height: 110)
    static let rimLocal = CGPoint(x: 65, y: 64)        // top edge of the front wall, view coords (y up)
    static let frontRect = CGRect(x: 17, y: 10, width: 96, height: 54)

    let back: CatPanel
    let front: CatPanel
    private let backView: BoxView
    private let frontView: BoxView
    private(set) var scale: CGFloat
    private(set) var originCG: CGPoint        // top-left of the window in CG coords
    var floating = true { didSet { applyLevel() } }
    var onMoved: (() -> Void)?
    private var dragOffset: CGPoint?

    init(scale: CGFloat, originCG: CGPoint) {
        self.scale = scale
        self.originCG = originCG
        let size = CGSize(width: HomeBox.viewSize.width * scale, height: HomeBox.viewSize.height * scale)
        back = CatPanel(size: size)
        front = CatPanel(size: size)
        backView = BoxView(part: .back)
        frontView = BoxView(part: .front)
        for (p, v) in [(back, backView), (front, frontView)] {
            v.frame = NSRect(origin: .zero, size: size)
            v.box = self
            p.contentView = v
        }
        applyLevel()
        place()
    }

    var frameCG: CGRect {
        CGRect(origin: originCG, size: CGSize(width: HomeBox.viewSize.width * scale, height: HomeBox.viewSize.height * scale))
    }

    var level: NSWindow.Level { floating ? .floating : .desktopCat }

    /// The point on the rim where a cat in the box rests its paws.
    var rim: CGPoint {
        CGPoint(x: originCG.x + HomeBox.rimLocal.x * scale, y: originCG.y + (HomeBox.viewSize.height - HomeBox.rimLocal.y) * scale)
    }

    var surface: Surface {
        Surface(ref: .box, y: rim.y, minX: rim.x - 10 * scale, maxX: rim.x + 10 * scale,
                z: floating ? World.topZ - 1 : -0.5)
    }

    /// Clickable part (the front wall), in CG coords.
    var hitRect: CGRect {
        let f = HomeBox.frontRect
        return CGRect(x: originCG.x + f.minX * scale, y: originCG.y + (HomeBox.viewSize.height - f.maxY) * scale,
                      width: f.width * scale, height: f.height * scale)
    }

    func setScale(_ s: CGFloat) {
        let bottomCenter = CGPoint(x: frameCG.midX, y: frameCG.maxY)
        scale = s
        let size = CGSize(width: HomeBox.viewSize.width * s, height: HomeBox.viewSize.height * s)
        for p in [back, front] { p.setContentSize(size); p.contentView?.frame = NSRect(origin: .zero, size: size) }
        originCG = CGPoint(x: bottomCenter.x - size.width / 2, y: bottomCenter.y - size.height)
        place()
    }

    func move(rimTo p: CGPoint) {
        originCG = CGPoint(x: p.x - HomeBox.rimLocal.x * scale, y: p.y - (HomeBox.viewSize.height - HomeBox.rimLocal.y) * scale)
        place()
        onMoved?()
    }

    func place() {
        let r = Coords.cocoa(fromCG: frameCG)
        back.setFrameOrigin(r.origin)
        front.setFrameOrigin(r.origin)
        World.shared.boxSurface = surface
        World.shared.boxFloating = floating
        backView.needsDisplay = true
        frontView.needsDisplay = true
    }

    func show() {
        back.orderFrontRegardless()
        front.order(.above, relativeTo: back.windowNumber)
    }

    func hide() { back.orderOut(nil); front.orderOut(nil) }

    private func applyLevel() {
        back.level = level
        front.level = level
        if back.isVisible { show() }
        World.shared.boxFloating = floating
        World.shared.boxSurface = surface
    }

    /// Called every frame: only the front wall catches the mouse.
    func updateMouse(_ m: CGPoint) {
        let over = hitRect.contains(m) || dragOffset != nil
        if front.ignoresMouseEvents == over { front.ignoresMouseEvents = !over }
    }

    // Dragging the box around.
    func mouseDown() {
        let m = Coords.mouse
        dragOffset = CGPoint(x: m.x - originCG.x, y: m.y - originCG.y)
    }

    func mouseDragged() {
        guard let o = dragOffset else { return }
        let m = Coords.mouse
        originCG = CGPoint(x: m.x - o.x, y: m.y - o.y)
        place()
    }

    func mouseUp() {
        dragOffset = nil
        onMoved?()
    }
}

final class BoxView: NSView {
    enum Part { case back, front }
    let part: Part
    weak var box: HomeBox?

    init(part: Part) {
        self.part = part
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { box?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { box?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { box?.mouseUp() }

    static let card = rgb(0xDDA468)
    static let cardDark = rgb(0xB77B45)
    static let cardInside = rgb(0x9C6537)
    static let line = rgb(0x6E4423)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let box else { return }
        ctx.clear(bounds)
        ctx.scaleBy(x: box.scale, y: box.scale)
        Self.paint(ctx, part)
    }

    /// Draw one wall in view points, y up. Also paints the README pictures.
    static func paint(_ ctx: CGContext, _ part: Part) {
        ctx.setLineJoin(.round)
        ctx.setLineWidth(1.6)
        ctx.setStrokeColor(BoxView.line)
        part == .back ? drawBack(ctx) : drawFront(ctx)
    }

    private static func quad(_ ctx: CGContext, _ pts: [CGPoint], _ color: CGColor) {
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.setFillColor(color)
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawBack(_ ctx: CGContext) {
        // Open flaps, splayed outward.
        quad(ctx, [CGPoint(x: 26, y: 76), CGPoint(x: 104, y: 76), CGPoint(x: 98, y: 96), CGPoint(x: 32, y: 96)], BoxView.cardDark)
        quad(ctx, [CGPoint(x: 18, y: 63), CGPoint(x: 26, y: 76), CGPoint(x: 6, y: 92), CGPoint(x: 2, y: 74)], BoxView.card)
        quad(ctx, [CGPoint(x: 112, y: 63), CGPoint(x: 104, y: 76), CGPoint(x: 124, y: 92), CGPoint(x: 128, y: 74)], BoxView.card)
        // The inside of the box.
        quad(ctx, [CGPoint(x: 18, y: 63), CGPoint(x: 112, y: 63), CGPoint(x: 104, y: 76), CGPoint(x: 26, y: 76)], BoxView.cardInside)
    }

    private static func drawFront(_ ctx: CGContext) {
        let r = HomeBox.frontRect
        let body = CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.addPath(body)
        ctx.setFillColor(BoxView.card)
        ctx.drawPath(using: .fillStroke)
        ctx.saveGState()
        ctx.addPath(body); ctx.clip()
        ctx.setFillColor(BoxView.cardDark.copy(alpha: 0.45)!)
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 7))
        // Packing tape
        ctx.setFillColor(rgb(0xEBCB98, 0.9))
        ctx.fill(CGRect(x: r.midX - 7, y: r.maxY - 18, width: 14, height: 18))
        ctx.restoreGState()
        // Paw print stamp
        ctx.setFillColor(rgb(0xA0612F, 0.75))
        let c = CGPoint(x: r.midX, y: r.minY + 21)
        ctx.fillEllipse(in: CGRect(x: c.x - 7, y: c.y - 6, width: 14, height: 11))
        for (dx, dy) in [(-8.5, 6.5), (-3, 10), (3, 10), (8.5, 6.5)] as [(CGFloat, CGFloat)] {
            ctx.fillEllipse(in: CGRect(x: c.x + dx - 2.6, y: c.y + dy - 2.8, width: 5.2, height: 5.6))
        }
        // Rim
        ctx.setStrokeColor(rgb(0xF2CF9C))
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: r.minX + 3, y: r.maxY - 2))
        ctx.addLine(to: CGPoint(x: r.maxX - 3, y: r.maxY - 2))
        ctx.strokePath()
    }
}
