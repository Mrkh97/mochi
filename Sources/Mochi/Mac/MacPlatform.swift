import AppKit
import ServiceManagement

// The shared code draws with CoreGraphics on both platforms (Windows has its own stand-in).
@_exported import CoreGraphics

extension Coords {
    /// Cached: NSScreen.screens builds a fresh array on every call, which adds up at 60 fps.
    static var primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0
    static func cg(fromCocoa r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func cg(fromCocoa p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
}

/// Window-info keys as NSStrings, made once.
private enum K {
    static let layer = kCGWindowLayer as NSString
    static let number = kCGWindowNumber as NSString
    static let pid = kCGWindowOwnerPID as NSString
    static let bounds = kCGWindowBounds as NSString
    static let alpha = kCGWindowAlpha as NSString
    static let onscreen = kCGWindowIsOnscreen as NSString
    static let owner = kCGWindowOwnerName as NSString
}

final class MacPlatform: Platform {
    private let ownPID = getpid()
    /// The right-click being handled, so a cat's menu pops up from it.
    static var menuEvent: (NSEvent, NSView)?

    func now() -> Double { CACurrentMediaTime() }

    var mouse: CGPoint { Coords.cg(fromCocoa: NSEvent.mouseLocation) }

    func screens() -> [ScreenInfo] {
        Coords.primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { ScreenInfo(frame: Coords.cg(fromCocoa: $0.frame), visible: Coords.cg(fromCocoa: $0.visibleFrame)) }
    }

    func windowList() -> (windows: [WinInfo], stack: [CGWindowID]) {
        // Read the CF objects directly; bridging the whole list into Swift dictionaries is several times slower.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else { return ([], []) }
        var result: [WinInfo] = []
        var order: [CGWindowID] = []
        for case let w as NSDictionary in list {
            guard let id = (w[K.number] as? NSNumber)?.uint32Value,
                  let pid = (w[K.pid] as? NSNumber)?.int32Value else { continue }
            // Our own windows at every level (the box and bowls float), so a cat in the box can be checked too.
            if pid == ownPID { order.append(id); continue }
            guard (w[K.layer] as? NSNumber)?.intValue == 0,
                  let bd = w[K.bounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bd) else { continue }
            order.append(id)
            if (w[K.owner] as? String) == "Mochi" { continue }   // another copy's cats
            if ((w[K.alpha] as? NSNumber)?.doubleValue ?? 1) < 0.05 { continue }
            result.append(WinInfo(id: id, pid: pid, frame: frame, z: 0))
        }
        return (result, order)
    }

    func liveFrame(of id: CGWindowID) -> CGRect? {
        var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
        guard let arr = CFArrayCreate(kCFAllocatorDefault, &ids, 1, nil),
              let info = (CGWindowListCreateDescriptionFromArray(arr) as NSArray?)?.firstObject as? NSDictionary,
              (info[K.onscreen] as? NSNumber)?.boolValue ?? true,
              let bd = info[K.bounds] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bd)
    }

    func isOwn(_ id: CGWindowID) -> Bool { NSApp.window(withWindowNumber: Int(id)) != nil }

    func makeSprite(size: CGSize) -> Sprite { MacSprite(size: size) }

    // MARK: Text

    /// Rendered glyph strings, cached: building a rounded font every frame was the most expensive part of drawing.
    private var textCache: [String: (CTLine, CGSize)] = [:]

    func drawText(_ text: String, size: CGFloat, ink: Ink, in ctx: CGContext) {
        let key = "\(text)|\(Int(size))|\(ink.hashValue)"
        let entry: (CTLine, CGSize)
        if let e = textCache[key] {
            entry = e
        } else {
            let font = NSFont.systemFont(ofSize: CGFloat(Int(size)), weight: .heavy)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: CGFloat(Int(size))) } ?? font
            let str = NSAttributedString(string: text, attributes: [
                .font: rounded, .foregroundColor: Self.color(ink),
                .strokeColor: NSColor.white, .strokeWidth: -3.0,
            ])
            let line = CTLineCreateWithAttributedString(str)
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            entry = (line, b.size)
            textCache[key] = entry
        }
        ctx.textPosition = CGPoint(x: -entry.1.width / 2, y: -entry.1.height / 2)
        CTLineDraw(entry.0, ctx)
    }

    private static func color(_ ink: Ink) -> NSColor {
        switch ink {
        case .systemBrown: return .systemBrown
        case .systemPink: return .systemPink
        case .systemRed: return .systemRed
        case let .srgb(r, g, b): return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    // MARK: Moving other apps' windows

    var canMoveWindows: Bool { MacNudger.shared.trusted }
    func requestWindowAccess() { MacNudger.shared.requestPermission() }
    func jiggle(_ win: WinInfo, amplitude: CGFloat) { MacNudger.shared.jiggle(win, amplitude: amplitude) }

    // MARK: App

    func popUpMenu(_ items: [MenuItem]) {
        let menu = NSMenu()
        MenuBuilder.fill(menu, with: items)
        if let (event, view) = Self.menuEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    func showAlert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    func quit() { NSApp.terminate(nil) }
}

/// Turns the shared menu description into an NSMenu.
enum MenuBuilder {
    /// Holds a menu item's closure; NSMenuItem only keeps a weak reference to its target,
    /// so the item's representedObject owns it.
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func perform(_ sender: Any?) { run() }
    }

    static func fill(_ menu: NSMenu, with items: [MenuItem]) {
        menu.removeAllItems()
        for it in items {
            switch it.kind {
            case .separator:
                menu.addItem(.separator())
            case .label:
                let line = NSMenuItem(title: it.title, action: nil, keyEquivalent: "")
                line.isEnabled = false
                menu.addItem(line)
            case .action(let run):
                let a = Action(run)
                let i = NSMenuItem(title: it.title, action: #selector(Action.perform(_:)), keyEquivalent: it.key)
                i.target = a
                i.representedObject = a
                i.state = it.checked ? .on : .off
                menu.addItem(i)
            case .submenu(let children):
                let i = NSMenuItem(title: it.title, action: nil, keyEquivalent: "")
                if it.enabled && !children.isEmpty {
                    let sub = NSMenu()
                    fill(sub, with: children)
                    i.submenu = sub
                }
                menu.addItem(i)
            }
        }
    }
}
