import CDirect2D
import Foundation
import WinSDK

/// A sprite on Windows: a layered, never-activated popup window. Its picture is drawn with Direct2D
/// and handed over whole with UpdateLayeredWindow, sized to just the part that has something in it.
final class WinSprite: Sprite {
    let hwnd: HWND
    weak var content: SpriteContent?
    var size: CGSize
    var origin = CGPoint.zero {
        didSet { if origin != oldValue { moved = true } }
    }
    var level: SpriteLevel = .normal {
        didSet { if level != oldValue { applyLevel() } }
    }
    var clickThrough = true {
        didSet { if clickThrough != oldValue { applyStyle() } }
    }

    private var dirty = true
    private var moved = false
    /// The drawn part, in the sprite's points (y up), as of the last frame.
    private var drawn = CGRect.zero
    private var fadeStart: Double?

    static let className = "MochiSprite"

    init(size: CGSize) {
        self.size = size
        hwnd = Win32.createWindow(className: Self.className,
                                  exStyle: DWORD(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT),
                                  style: DWORD(bitPattern: Int32(bitPattern: WS_POPUP)))
        WinSprite.all[Win32.key(hwnd)] = Weak(self)
    }

    deinit {
        WinSprite.all[Win32.key(hwnd)] = nil
        DestroyWindow(hwnd)
    }

    var id: CGWindowID { Win32.id(hwnd) }
    var isShown: Bool { IsWindowVisible(hwnd) }
    /// Windows can't cheaply tell whether other windows cover this one, so a shown sprite counts as visible.
    var isVisible: Bool { isShown }

    func setNeedsDisplay() { dirty = true }

    // MARK: Stacking

    private var isTopmost: Bool { level == .floating || level == .carried || level == .toy }

    private func rank(_ l: SpriteLevel) -> Int {
        switch l {
        case .desktop: return 0
        case .normal: return 1
        case .floating: return 2
        case .carried: return 3
        case .toy: return 4
        }
    }

    private func place(after: HWND?, show: Bool = true) {
        var flags = UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER)
        if show { flags |= UINT(SWP_SHOWWINDOW) }
        SetWindowPos(hwnd, after, 0, 0, 0, 0, flags)
    }

    private func applyLevel() {
        // Only the band changes here; callers then order the sprite within it.
        place(after: isTopmost ? Win32.topmost : Win32.notTopmost, show: false)
    }

    func orderFront() {
        switch level {
        case .desktop:
            // Just above the desktop itself (and its icons), behind every window.
            guard let desktop = GetShellWindow() else { return place(after: Win32.bottom) }
            let above = GetWindow(desktop, UINT(GW_HWNDPREV))
            if above == hwnd { show() } else { place(after: above) }
        case .normal:
            place(after: Win32.top)
        case .floating, .carried, .toy:
            // Levels are separate bands on macOS; keep ours in order inside the topmost band.
            let higher = WinSprite.all.values.compactMap(\.value).filter { $0 !== self && $0.isShown && rank($0.level) > rank(level) }
            place(after: Win32.lowest(higher.map(\.hwnd)) ?? Win32.topmost)
        }
    }

    func order(above id: CGWindowID) {
        let target = Win32.hwnd(id)
        guard IsWindow(target) else { return orderFront() }
        let above = GetWindow(target, UINT(GW_HWNDPREV))
        if above == hwnd { return show() }
        if let above, isTopmost || !Win32.isTopmost(above) {
            place(after: above)
        } else {
            place(after: isTopmost ? Win32.topmost : Win32.top)
        }
    }

    func order(below id: CGWindowID) {
        let target = Win32.hwnd(id)
        guard IsWindow(target) else { return orderFront() }
        place(after: target)
    }

    private func show() {
        if !isShown { ShowWindow(hwnd, SW_SHOWNOACTIVATE) }
    }

    func orderOut() {
        ShowWindow(hwnd, SW_HIDE)
        fadeStart = nil
    }

    func fadeOut() {
        fadeStart = platform.now()
        dirty = true
    }

    private func applyStyle() {
        var ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
        let transparent = LONG_PTR(WS_EX_TRANSPARENT)
        ex = clickThrough ? ex | transparent : ex & ~transparent
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex)
    }

    // MARK: Drawing

    /// Draws the sprite if it asked to be, or moves it if it only moved. Called once per frame.
    func flush(_ canvas: OpaquePointer, scale k: CGFloat) {
        if let start = fadeStart {
            if platform.now() - start >= 0.5 { orderOut(); return }
            dirty = true
        }
        guard isShown || fadeStart != nil else { return }
        if dirty {
            dirty = false
            moved = false
            render(canvas, scale: k)
        } else if moved {
            moved = false
            let p = pixelOrigin(scale: k)
            SetWindowPos(hwnd, nil, p.x, p.y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER))
        }
    }

    private func pixelOrigin(scale k: CGFloat) -> POINT {
        POINT(x: LONG(((origin.x + drawn.minX) * k).rounded()),
              y: LONG(((origin.y + size.height - drawn.maxY) * k).rounded()))
    }

    private func render(_ canvas: OpaquePointer, scale k: CGFloat) {
        var bounds = content?.drawingBounds ?? CGRect(origin: .zero, size: size)
        if bounds.isEmpty { bounds = CGRect(x: 0, y: 0, width: 1 / k, height: 1 / k) }
        drawn = bounds
        let w = max(1, Int((bounds.width * k).rounded(.up))), h = max(1, Int((bounds.height * k).rounded(.up)))
        guard mg_canvas_begin(canvas, Int32(w), Int32(h)) != 0 else { return }
        if let content, !(content.drawingBounds?.isEmpty ?? false) {
            let ctx = CGContext(canvas: canvas, width: w, height: h)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            content.draw(ctx)
        }
        guard mg_canvas_end(canvas) != 0 else { dirty = true; return }
        var dst = pixelOrigin(scale: k)
        var sz = SIZE(cx: LONG(w), cy: LONG(h))
        var src = POINT(x: 0, y: 0)
        let fade = fadeStart.map { 1 - (platform.now() - $0) / 0.5 } ?? 1
        var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0,
                                  SourceConstantAlpha: BYTE(max(0, min(255, fade * 255))), AlphaFormat: BYTE(AC_SRC_ALPHA))
        let dc = HDC(OpaquePointer(mg_canvas_dc(canvas)))
        UpdateLayeredWindow(hwnd, nil, &dst, &sz, dc, &src, 0, &blend, DWORD(ULW_ALPHA))
    }

    // MARK: Mouse

    func handle(_ msg: UINT, _ wParam: WPARAM) -> LRESULT? {
        switch Int32(msg) {
        case WM_MOUSEACTIVATE:
            return LRESULT(MA_NOACTIVATE)
        case WM_LBUTTONDOWN:
            SetCapture(hwnd)
            content?.mouseDown()
            return 0
        case WM_MOUSEMOVE:
            if GetCapture() == hwnd && (wParam & WPARAM(MK_LBUTTON)) != 0 { content?.mouseDragged() }
            return 0
        case WM_LBUTTONUP:
            if GetCapture() == hwnd { ReleaseCapture() }
            content?.mouseUp()
            return 0
        case WM_RBUTTONUP:
            content?.rightMouseDown()
            return 0
        case WM_CLOSE:
            // Asked to close from outside (taskkill, an installer): that means the app.
            platform.quit()
            return 0
        default:
            return nil
        }
    }

    // MARK: Registry of live sprites

    struct Weak { weak var value: WinSprite?; init(_ v: WinSprite) { value = v } }
    static var all: [UInt: Weak] = [:]

    static func sprite(for hwnd: HWND) -> WinSprite? { all[Win32.key(hwnd)]?.value }
}
