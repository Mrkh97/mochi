import AppKit

/// A transparent, non-activating panel that never steals focus from the app you're using.
final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // AppKit pushes windows down out from under the menu bar, which made cats on a window just below it
    // float in mid-air, and would stop them crossing to a display above. Cats go where they're put.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    convenience init(size: CGSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }
}

extension NSWindow.Level {
    static let desktopCat = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    static let carried = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
}

final class CatView: NSView {
    weak var cat: Cat?
    var anchor: CGPoint = .zero
    var onContextMenu: ((NSEvent, NSView) -> Void)?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Render on the CPU into our own bitmap and hand a layer the finished image. Letting AppKit
    // draw the view directly made the system reserve ~300 MB of GPU buffers for accelerated drawing.
    override var wantsUpdateLayer: Bool { true }
    // Two bitmaps used alternately, so drawing a frame never forces a copy of the one on screen.
    private var bitmaps: [CGContext?] = [nil, nil]
    private var current = 0
    /// Only the box around the cat is drawn and uploaded, not the whole (mostly empty) window.
    private let sprite = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "frame": NSNull()]
        layer?.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Cat-local box that holds everything drawn this frame (effects that drift further get clipped).
    private func box(for cat: Cat) -> CGRect {
        let p = cat.pose
        let hangs = cat.shownView == .front && p.fBody.y < 5
        return hangs ? CGRect(x: -72, y: -112, width: 144, height: 240) : CGRect(x: -72, y: -14, width: 144, height: 142)
    }

    override func updateLayer() {
        guard let cat else { return }
        if case .hidden? = cat.overlay {
            sprite.contents = nil
            return
        }
        let t0 = CACurrentMediaTime()
        defer { Perf.add("draw", CACurrentMediaTime() - t0) }
        let bs = window?.backingScaleFactor ?? 2
        let b = box(for: cat)
        let frame = CGRect(x: anchor.x + b.minX * cat.scale, y: anchor.y + b.minY * cat.scale,
                           width: b.width * cat.scale, height: b.height * cat.scale)
        let w = Int((frame.width * bs).rounded(.up)), h = Int((frame.height * bs).rounded(.up))
        current ^= 1
        bitmaps[current] = displayBitmap(reuse: bitmaps[current], width: w, height: h, window: window)
        guard let ctx = bitmaps[current] else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.scaleBy(x: bs, y: bs)
        ctx.translateBy(x: -b.minX * cat.scale, y: -b.minY * cat.scale)
        ctx.scaleBy(x: cat.scale, y: cat.scale)
        ctx.saveGState()
        if cat.depth == .inBox {
            // Toes and tail stay inside the box instead of poking out under it.
            let bottom = HomeBox.frontRect.minY - HomeBox.rimLocal.y
            ctx.clip(to: CGRect(x: -200, y: bottom, width: 400, height: 400))
        }
        ctx.scaleBy(x: cat.renderScaleX, y: 1)
        if case .fight(let other)? = cat.overlay {
            CatRenderer(coat: cat.coat, time: cat.time).drawFightCloud(ctx, other: other)
        } else {
            var pose = cat.displayPose
            pose.view = cat.shownView
            CatRenderer(coat: cat.coat, time: cat.time).draw(ctx, pose: pose)
        }
        ctx.restoreGState()
        cat.effects.draw(ctx)
        ctx.restoreGState()
        sprite.frame = frame
        sprite.contentsScale = bs
        sprite.contents = ctx.makeImage()
    }

    override func mouseDown(with event: NSEvent) { cat?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { cat?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { cat?.mouseUp() }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event, self) }
}

/// Debug timing (MOCHI_DEBUG): prints average cost per call every few seconds.
enum Perf {
    static var sums: [String: (Double, Int)] = [:]
    static var lastPrint = CACurrentMediaTime()
    static func add(_ key: String, _ dt: Double) {
        guard Cat.debug else { return }
        let v = sums[key] ?? (0, 0)
        sums[key] = (v.0 + dt, v.1 + 1)
        let now = CACurrentMediaTime()
        if now - lastPrint > 5 {
            let span = now - lastPrint
            let line = sums.map { String(format: "%@ %.3fms x%.0f/s", $0.key, $0.value.0 / Double($0.value.1) * 1000, Double($0.value.1) / span) }.sorted().joined(separator: "  ")
            print("perf:", line)
            sums = [:]
            lastPrint = now
        }
    }
}
