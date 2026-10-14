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
    static let toy = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)

    init(_ level: SpriteLevel) {
        switch level {
        case .desktop: self = .desktopCat
        case .normal: self = .normal
        case .floating: self = .floating
        case .carried: self = .carried
        case .toy: self = .toy
        }
    }
}

/// A sprite on macOS: a `CatPanel` showing a `SpriteView`.
final class MacSprite: Sprite {
    let panel: CatPanel
    private let view: SpriteView

    init(size: CGSize) {
        panel = CatPanel(size: size)
        view = SpriteView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
    }

    var id: CGWindowID { CGWindowID(panel.windowNumber) }

    var content: SpriteContent? {
        get { view.content }
        set { view.content = newValue }
    }

    var size: CGSize {
        get { panel.frame.size }
        set {
            panel.setContentSize(newValue)
            view.frame = NSRect(origin: .zero, size: newValue)
        }
    }

    var origin: CGPoint {
        get { CGPoint(x: panel.frame.minX, y: Coords.primaryHeight - panel.frame.maxY) }
        set {
            let o = CGPoint(x: newValue.x, y: Coords.primaryHeight - newValue.y - panel.frame.height)
            if panel.frame.origin != o { panel.setFrameOrigin(o) }
        }
    }

    var level: SpriteLevel = .normal {
        didSet { panel.level = NSWindow.Level(level) }
    }

    var clickThrough: Bool {
        get { panel.ignoresMouseEvents }
        set { panel.ignoresMouseEvents = newValue }
    }

    var isShown: Bool { panel.isVisible }
    var isVisible: Bool { panel.occlusionState.contains(.visible) }

    func orderFront() { panel.orderFrontRegardless() }
    func order(above id: CGWindowID) { panel.order(.above, relativeTo: Int(id)) }
    func order(below id: CGWindowID) { panel.order(.below, relativeTo: Int(id)) }
    func orderOut() { panel.orderOut(nil) }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
        })
    }

    func setNeedsDisplay() { view.needsDisplay = true }
}

/// An offscreen bitmap in the window's own colour space. Drawing in sRGB on a P3 display made
/// Core Animation convert every pixel of every frame on the CPU, which was most of our CPU time.
func displayBitmap(reuse old: CGContext?, width w: Int, height h: Int, window: NSWindow?) -> CGContext? {
    let space = window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    if let old, old.width == w, old.height == h, old.colorSpace == space { return old }
    return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
}

final class SpriteView: NSView {
    weak var content: SpriteContent?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Render on the CPU into our own bitmap and hand a layer the finished image. Letting AppKit
    // draw the view directly made the system reserve ~300 MB of GPU buffers for accelerated drawing.
    override var wantsUpdateLayer: Bool { true }
    // Two bitmaps used alternately, so drawing a frame never forces a copy of the one on screen.
    private var bitmaps: [CGContext?] = [nil, nil]
    private var current = 0
    /// Only the part the content asks for is drawn and uploaded, not the whole (mostly empty) window.
    private let sprite = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "frame": NSNull()]
        layer?.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        guard let content else { return }
        let frame = content.drawingBounds ?? bounds
        guard !frame.isEmpty else {
            sprite.contents = nil
            return
        }
        let bs = window?.backingScaleFactor ?? 2
        let w = Int((frame.width * bs).rounded(.up)), h = Int((frame.height * bs).rounded(.up))
        current ^= 1
        bitmaps[current] = displayBitmap(reuse: bitmaps[current], width: w, height: h, window: window)
        guard let ctx = bitmaps[current] else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.scaleBy(x: bs, y: bs)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        content.draw(ctx)
        ctx.restoreGState()
        sprite.frame = frame
        sprite.contentsScale = bs
        sprite.contents = ctx.makeImage()
    }

    override func mouseDown(with event: NSEvent) { content?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { content?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { content?.mouseUp() }
    override func rightMouseDown(with event: NSEvent) {
        MacPlatform.menuEvent = (event, self)
        content?.rightMouseDown()
        MacPlatform.menuEvent = nil
    }
}
