import Foundation

/// Everything Mochi needs from the operating system. macOS and Windows each provide one
/// (in Mac/ and Windows/); the rest of the app only talks to the system through this.
///
/// Global coordinates have their origin at the top-left of the primary display and y growing
/// downward, in points.
protocol Platform: AnyObject {
    /// Seconds on a monotonic clock.
    func now() -> Double

    /// The pointer, in global coordinates.
    var mouse: CGPoint { get }

    /// Every display: its full frame, and the part not taken by the menu bar, Dock or taskbar.
    func screens() -> [ScreenInfo]

    /// Other apps' ordinary windows front to back (`z` is filled in by `World`), and the stacking
    /// order of those plus every window of ours.
    func windowList() -> (windows: [WinInfo], stack: [CGWindowID])

    /// Where one window is right now; nil once it's closed or hidden.
    func liveFrame(of id: CGWindowID) -> CGRect?

    func isOwn(_ id: CGWindowID) -> Bool

    /// A transparent window to draw a cat, a wall of the box, the bowls or the toy in.
    func makeSprite(size: CGSize) -> Sprite

    /// Draws a short word centred on the origin (y up): heavy rounded letters with a white outline.
    func drawText(_ text: String, size: CGFloat, ink: Ink, in ctx: CGContext)

    /// Whether other apps' windows can be moved. macOS needs the Accessibility permission first.
    var canMoveWindows: Bool { get }
    func requestWindowAccess()

    /// Pulls a window down by `amplitude` points and lets it bob back (a cat's weight yanking on it).
    func jiggle(_ win: WinInfo, amplitude: CGFloat)

    /// Shows a menu at the pointer (right-clicking a cat).
    func popUpMenu(_ items: [MenuItem])

    /// Whether Mochi starts when you log in.
    var opensAtLogin: Bool { get }
    func setOpensAtLogin(_ on: Bool) throws

    func showAlert(_ title: String, _ message: String)
    func quit()
}

/// Set once at launch.
var platform: Platform!

/// How high a sprite sits in the window stack.
enum SpriteLevel {
    case desktop     // behind every window, just above the desktop icons
    case normal      // among ordinary windows
    case floating    // above ordinary windows (the box and bowls, unless they're set to stay down)
    case carried     // above the box and bowls (a cat being carried)
    case toy         // above everything else of ours
}

/// A borderless, transparent window. Clicks pass through it while `clickThrough` is on.
protocol Sprite: AnyObject {
    var id: CGWindowID { get }
    var size: CGSize { get set }
    /// Top-left corner, in global coordinates.
    var origin: CGPoint { get set }
    var level: SpriteLevel { get set }
    var clickThrough: Bool { get set }
    /// Ordered in (whether or not other windows cover it).
    var isShown: Bool { get }
    /// Ordered in and not completely covered by other windows.
    var isVisible: Bool { get }
    var content: SpriteContent? { get set }

    func orderFront()
    func order(above id: CGWindowID)
    func order(below id: CGWindowID)
    func orderOut()
    /// Fades away, then orders out.
    func fadeOut()
    func setNeedsDisplay()
}

/// What a sprite shows, and who hears about clicks on it.
protocol SpriteContent: AnyObject {
    /// The part of the sprite that needs drawing this frame, in its points with y up.
    /// nil means all of it.
    var drawingBounds: CGRect? { get }
    /// Draws in the sprite's points: origin at the bottom-left, y up.
    func draw(_ ctx: CGContext)
    func mouseDown()
    func mouseDragged()
    func mouseUp()
    func rightMouseDown()
}

extension SpriteContent {
    var drawingBounds: CGRect? { nil }
    func mouseDown() {}
    func mouseDragged() {}
    func mouseUp() {}
    func rightMouseDown() {}
}

/// Colours for the floating words. The named ones follow the system palette.
enum Ink: Hashable {
    case systemBrown, systemPink, systemRed
    case srgb(CGFloat, CGFloat, CGFloat)
}

/// One line of a menu, the same on every platform (the menu bar menu, the tray menu, a cat's context menu).
struct MenuItem {
    enum Kind {
        case action(() -> Void)
        case submenu([MenuItem])
        case label
        case separator
    }
    var title: String
    var kind: Kind
    var checked = false
    var enabled = true
    /// Keyboard shortcut shown on macOS (with ⌘).
    var key = ""

    static let separator = MenuItem(title: "", kind: .separator)

    static func action(_ title: String, key: String = "", checked: Bool = false, _ run: @escaping () -> Void) -> MenuItem {
        MenuItem(title: title, kind: .action(run), checked: checked, key: key)
    }

    static func label(_ title: String) -> MenuItem { MenuItem(title: title, kind: .label, enabled: false) }

    static func submenu(_ title: String, enabled: Bool = true, _ items: [MenuItem]) -> MenuItem {
        MenuItem(title: title, kind: .submenu(items), enabled: enabled)
    }
}
