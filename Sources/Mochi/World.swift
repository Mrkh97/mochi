import AppKit

/// Global coordinates in this app are CoreGraphics "global display" coordinates:
/// origin at the top-left of the primary display, y grows downward. That is what the
/// window server and the Accessibility API use, so window rectangles need no conversion.
enum Coords {
    /// Cached: NSScreen.screens builds a fresh array on every call, which adds up at 60 fps.
    static var primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0
    static func cg(fromCocoa r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func cocoa(fromCG r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func cg(fromCocoa p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    static var mouse: CGPoint { cg(fromCocoa: NSEvent.mouseLocation) }
}

struct ScreenInfo {
    let frame: CGRect     // CG coords
    let visible: CGRect   // CG coords, excludes menu bar and Dock
    var floorY: CGFloat { visible.maxY - 3 }
}

struct WinInfo {
    let id: CGWindowID
    let pid: pid_t
    var frame: CGRect
    var z: Int            // larger = closer to the viewer
}

/// Something a cat can stand on.
enum SurfaceRef: Equatable {
    case floor(Int)            // index into World.screens
    case window(CGWindowID)
    case box
    case bowls
}

struct Surface {
    let ref: SurfaceRef
    let y: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let z: Double
    var width: CGFloat { maxX - minX }
    func clamp(_ x: CGFloat) -> CGFloat { min(maxX, max(minX, x)) }
}

/// Where a cat sits in the window stack.
enum Depth: Equatable {
    case desktop                 // behind every window, just above the wallpaper icons
    case above(CGWindowID)       // directly in front of that window
    case top                     // in front of every normal window (being carried)
    case inBox                   // between the box's back and front walls
    case onBox                   // in front of the box
    case atBowls                 // just behind the bowls, face in the food
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

final class World {
    static let shared = World()

    private(set) var windows: [WinInfo] = []          // real app windows, front to back
    private(set) var stack: [CGWindowID] = []         // every layer-0 window plus all of ours, front to back
    private(set) var screens: [ScreenInfo] = []
    private var byID: [CGWindowID: Int] = [:]
    private(set) var prevZ: [CGWindowID: Int] = [:]       // stacking from the previous refresh
    private let ownPID = getpid()
    var boxSurface: Surface?                          // published by the home box
    var bowlsSurface: Surface?                        // published by the food & water bowls
    var boxFloating = true

    static let topZ = 1_000_000.0

    func refreshScreens() {
        Coords.primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        screens = NSScreen.screens.map { ScreenInfo(frame: Coords.cg(fromCocoa: $0.frame), visible: Coords.cg(fromCocoa: $0.visibleFrame)) }
    }

    func refresh() {
        if screens.isEmpty { refreshScreens() }
        // Read the CF objects directly; bridging the whole list into Swift dictionaries is several times slower.
        lastRefresh = CACurrentMediaTime()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else { return }
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
            if frame.width < 140 || frame.height < 130 { continue }
            if isOverlay(frame) { continue }
            result.append(WinInfo(id: id, pid: pid, frame: frame, z: 0))
        }
        for i in result.indices { result[i].z = result.count - i }
        prevZ = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.z) })
        windows = result
        stack = order
        byID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
    }

    /// Full-screen transparent overlays (screen recorders, cursor tools, …) are not real windows.
    private func isOverlay(_ f: CGRect) -> Bool {
        for s in screens {
            if abs(f.minX - s.frame.minX) < 3 && abs(f.minY - s.frame.minY) < 3 &&
                abs(f.width - s.frame.width) < 3 && abs(f.height - s.frame.height) < 3 { return true }
            // Normal titled windows can never overlap the menu bar.
            if s.visible.minY > s.frame.minY + 4, s.frame.contains(CGPoint(x: f.midX, y: f.minY + 1)),
               f.minY < s.visible.minY - 4 { return true }
        }
        return false
    }

    private(set) var lastRefresh: CFTimeInterval = 0

    /// The window list is surprisingly expensive (~3 ms), so it's only re-read when it matters.
    func refreshIfStale(_ maxAge: CFTimeInterval = 0.05) {
        if CACurrentMediaTime() - lastRefresh > maxAge { refresh() }
    }

    func window(_ id: CGWindowID) -> WinInfo? { byID[id].map { windows[$0] } }

    /// Cheap single-window lookup for following a moving window every frame.
    func liveFrame(_ id: CGWindowID) -> CGRect? {
        var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(id))]
        guard let arr = CFArrayCreate(kCFAllocatorDefault, &ids, 1, nil),
              let info = (CGWindowListCreateDescriptionFromArray(arr) as NSArray?)?.firstObject as? NSDictionary,
              (info[K.onscreen] as? NSNumber)?.boolValue ?? true,
              let bd = info[K.bounds] as? NSDictionary,
              let f = CGRect(dictionaryRepresentation: bd) else { return nil }
        if let i = byID[id] { windows[i].frame = f }
        return f
    }

    // MARK: Screens

    func screenIndex(at p: CGPoint) -> Int {
        if let i = screens.firstIndex(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }) { return i }
        var best = 0, bestD = CGFloat.greatestFiniteMagnitude
        for (i, s) in screens.enumerated() {
            let dx = max(s.frame.minX - p.x, 0, p.x - s.frame.maxX)
            let dy = max(s.frame.minY - p.y, 0, p.y - s.frame.maxY)
            if dx + dy < bestD { bestD = dx + dy; best = i }
        }
        return best
    }

    func screen(at p: CGPoint) -> ScreenInfo { screens.isEmpty ? ScreenInfo(frame: .zero, visible: .zero) : screens[screenIndex(at: p)] }

    // MARK: Depth

    func z(of depth: Depth) -> Double {
        switch depth {
        case .desktop: return -1
        case .above(let id): return window(id).map { Double($0.z) + 0.5 } ?? -1
        case .top: return World.topZ
        case .inBox, .onBox, .atBowls: return boxFloating ? World.topZ - 1 : -0.5
        }
    }

    /// Is `p` hidden by any window whose z lies in (lo, hi]?
    func covered(_ p: CGPoint, above lo: Double, upTo hi: Double = World.topZ) -> Bool {
        for w in windows where Double(w.z) > lo && Double(w.z) <= hi {
            if w.frame.insetBy(dx: 2, dy: 2).contains(p) { return true }
        }
        return false
    }

    /// Frontmost window covering `p`, if any.
    func frontmost(at p: CGPoint) -> WinInfo? { windows.first { $0.frame.contains(p) } }

    // MARK: Surfaces

    func surface(_ ref: SurfaceRef) -> Surface? {
        switch ref {
        case .floor(let i):
            guard i < screens.count else { return nil }
            let v = screens[i].visible
            return Surface(ref: ref, y: v.maxY - 3, minX: v.minX + 14, maxX: v.maxX - 14, z: -1)
        case .box:
            return boxSurface
        case .bowls:
            return bowlsSurface
        case .window(let id):
            guard let w = window(id) else { return nil }
            return windowTop(w)
        }
    }

    private func windowTop(_ w: WinInfo) -> Surface? {
        let s = screen(at: CGPoint(x: w.frame.midX, y: w.frame.minY + 2))
        // Leave room for the cat's head under the menu bar.
        guard w.frame.minY > s.visible.minY + 56 else { return nil }
        let minX = max(w.frame.minX + 18, s.visible.minX + 10)
        let maxX = min(w.frame.maxX - 18, s.visible.maxX - 10)
        guard maxX - minX > 40 else { return nil }
        return Surface(ref: .window(w.id), y: w.frame.minY, minX: minX, maxX: maxX, z: Double(w.z))
    }

    /// Every window top on the given screen.
    func windowSurfaces(screen i: Int) -> [Surface] {
        guard i < screens.count else { return [] }
        let sf = screens[i].frame
        return windows.compactMap { w in
            guard sf.contains(CGPoint(x: w.frame.midX, y: w.frame.minY + 2)) else { return nil }
            return windowTop(w)
        }
    }

    /// Where something falling straight down at `x` from `fromY` (with depth z) comes to rest.
    /// It passes behind anything in front of it and only lands on edges it can actually see.
    func landing(x: CGFloat, fromY: CGFloat, toY: CGFloat = .greatestFiniteMagnitude, z: Double, screen si: Int) -> Surface? {
        var best: Surface?
        for s in windowSurfaces(screen: si) where s.z <= z && x >= s.minX - 12 && x <= s.maxX + 12 {
            guard s.y > fromY - 0.5, s.y <= toY else { continue }
            if covered(CGPoint(x: x, y: s.y - 3), above: s.z, upTo: z) { continue }
            if best == nil || s.y < best!.y { best = s }
        }
        for b in [boxSurface, bowlsSurface].compactMap({ $0 }) where z >= b.z && x >= b.minX - 6 && x <= b.maxX + 6
            && b.y > fromY - 0.5 && b.y <= toY && (best == nil || b.y < best!.y) {
            best = b
        }
        if best == nil, let floor = surface(.floor(si)), floor.y > fromY - 0.5, floor.y <= toY { best = floor }
        return best
    }
}
