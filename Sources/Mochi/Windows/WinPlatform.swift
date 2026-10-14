import CDirect2D
import Foundation
import WinSDK

private final class Monitors { var list: [MONITORINFO] = [] }

/// Windows works in physical pixels (the process is per-monitor DPI aware). The rest of Mochi works
/// in points, like macOS: pixels divided by the primary display's scale, so cats come out the same
/// size as on a Mac.
final class WinPlatform: Platform {
    let canvas: OpaquePointer
    private(set) var scale: CGFloat = 1
    /// The window that owns menus (they need a foreground window of ours to close properly).
    var menuOwner: HWND?
    var onQuit: (() -> Void)?
    private let frequency: Double

    init() {
        guard let c = mg_canvas_create() else { fatalError("Direct2D isn't available") }
        canvas = c
        var f = LARGE_INTEGER()
        QueryPerformanceFrequency(&f)
        frequency = Double(f.QuadPart)
        updateScale()
    }

    func updateScale() {
        scale = CGFloat(GetDpiForSystem()) / 96
    }

    private func points(_ r: RECT) -> CGRect {
        CGRect(x: CGFloat(r.left) / scale, y: CGFloat(r.top) / scale,
               width: CGFloat(r.right - r.left) / scale, height: CGFloat(r.bottom - r.top) / scale)
    }

    func now() -> Double {
        var t = LARGE_INTEGER()
        QueryPerformanceCounter(&t)
        return Double(t.QuadPart) / frequency
    }

    var mouse: CGPoint {
        var p = POINT()
        GetCursorPos(&p)
        return CGPoint(x: CGFloat(p.x) / scale, y: CGFloat(p.y) / scale)
    }

    // MARK: Screens

    func screens() -> [ScreenInfo] {
        let found = Monitors()
        EnumDisplayMonitors(nil, nil, { monitor, _, _, data in
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            if GetMonitorInfoW(monitor, &info), let raw = UnsafeRawPointer(bitPattern: Int(data)) {
                Unmanaged<Monitors>.fromOpaque(raw).takeUnretainedValue().list.append(info)
            }
            return true
        }, LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque())))
        // The primary display first, as on macOS.
        let primary = DWORD(MONITORINFOF_PRIMARY)
        let sorted = found.list.filter { $0.dwFlags & primary != 0 } + found.list.filter { $0.dwFlags & primary == 0 }
        return sorted.map { ScreenInfo(frame: points($0.rcMonitor), visible: points($0.rcWork)) }
    }

    // MARK: Windows

    func windowList() -> (windows: [WinInfo], stack: [CGWindowID]) {
        var result: [WinInfo] = []
        var order: [CGWindowID] = []
        var h = GetTopWindow(nil)
        var count = 0
        while let w = h, count < 20_000 {
            h = GetWindow(w, UINT(GW_HWNDNEXT))
            count += 1
            guard IsWindowVisible(w) else { continue }
            let id = Win32.id(w)
            if WinSprite.sprite(for: w) != nil { order.append(id); continue }
            let ex = GetWindowLongPtrW(w, GWL_EXSTYLE)
            // Only ordinary windows, like macOS's layer 0: not always-on-top ones (the taskbar),
            // minimized ones, or ones on another virtual desktop.
            if ex & LONG_PTR(WS_EX_TOPMOST) != 0 || IsIconic(w) || isCloaked(w) { continue }
            let cls = Win32.className(w)
            if cls == "Progman" || cls == "WorkerW" { continue }   // the desktop
            order.append(id)
            if cls == WinSprite.className { continue }               // another copy's cats
            // Click-through overlays are not real windows.
            if ex & LONG_PTR(WS_EX_LAYERED) != 0 && ex & LONG_PTR(WS_EX_TRANSPARENT) != 0 { continue }
            guard let frame = frame(of: w) else { continue }
            var pid: DWORD = 0
            GetWindowThreadProcessId(w, &pid)
            result.append(WinInfo(id: id, pid: Int32(bitPattern: pid), frame: frame, z: 0))
        }
        return (result, order)
    }

    private func isCloaked(_ w: HWND) -> Bool {
        var cloaked: DWORD = 0
        let hr = DwmGetWindowAttribute(w, DWORD(DWMWA_CLOAKED.rawValue), &cloaked, DWORD(MemoryLayout<DWORD>.size))
        return hr == S_OK && cloaked != 0
    }

    /// The visible frame, without the invisible resize borders Windows adds around it.
    private func frame(of w: HWND) -> CGRect? {
        var r = RECT()
        if DwmGetWindowAttribute(w, DWORD(DWMWA_EXTENDED_FRAME_BOUNDS.rawValue), &r, DWORD(MemoryLayout<RECT>.size)) != S_OK {
            guard GetWindowRect(w, &r) else { return nil }
        }
        return points(r)
    }

    func liveFrame(of id: CGWindowID) -> CGRect? {
        guard let w = Win32.hwnd(id), IsWindow(w), IsWindowVisible(w), !IsIconic(w), !isCloaked(w) else { return nil }
        return frame(of: w)
    }

    func isOwn(_ id: CGWindowID) -> Bool {
        guard let w = Win32.hwnd(id) else { return false }
        return WinSprite.sprite(for: w) != nil
    }

    func makeSprite(size: CGSize) -> Sprite { WinSprite(size: size) }

    /// Draws every sprite that changed this frame.
    func flushSprites() {
        for s in WinSprite.all.values.compactMap(\.value) { s.flush(canvas, scale: scale) }
    }

    // MARK: Text

    func drawText(_ text: String, size: CGFloat, ink: Ink, in ctx: CGContext) {
        let pt = CGFloat(Int(size))
        // The outline is 3% of the type size, as on macOS.
        ctx.drawLetters(text, size: pt, color: Self.color(ink), outline: pt * 0.03)
    }

    /// The light-appearance values of the macOS system colours.
    private static func color(_ ink: Ink) -> CGColor {
        switch ink {
        case .systemBrown: return rgb(0xA2845E)
        case .systemPink: return rgb(0xFF2D55)
        case .systemRed: return rgb(0xFF3B30)
        case let .srgb(r, g, b): return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    // MARK: Moving other apps' windows

    var canMoveWindows: Bool { true }
    func requestWindowAccess() {}

    private var busy = Set<CGWindowID>()
    private let lock = NSLock()

    /// Damped spring: pulled down by `amplitude` points, then bobbing back into place.
    func jiggle(_ win: WinInfo, amplitude: CGFloat) {
        guard let w = Win32.hwnd(win.id), IsWindow(w), !IsZoomed(w) else { return }
        lock.lock()
        if busy.contains(win.id) { lock.unlock(); return }
        busy.insert(win.id)
        lock.unlock()
        let k = scale
        let key = UInt(bitPattern: w)
        Thread.detachNewThread { [self] in
            defer { lock.lock(); busy.remove(win.id); lock.unlock() }
            guard let w = HWND(bitPattern: key) else { return }
            var r = RECT()
            guard GetWindowRect(w, &r) else { return }
            let flags = UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS)
            let start = now()
            var t = 0.0
            while t < 0.75 {
                let offset = amplitude * 1.5 * CGFloat(exp(-5.0 * t) * sin(2 * .pi * 3.0 * t))
                SetWindowPos(w, nil, r.left, r.top + LONG((offset * k).rounded()), 0, 0, flags)
                WinSDK.Sleep(16)   // (plain Sleep is the cats' nap)
                t = now() - start
            }
            SetWindowPos(w, nil, r.left, r.top, 0, 0, flags)
        }
    }

    // MARK: Menus

    /// What the items of the open (or just closed) menu do, by command number.
    private var menuActions: [() -> Void] = []

    func popUpMenu(_ items: [MenuItem]) {
        guard let owner = menuOwner else { return }
        menuActions = []
        let menu = Self.build(items, &menuActions)
        defer { DestroyMenu(menu) }
        var p = POINT()
        GetCursorPos(&p)
        // The menu only closes on a click elsewhere if a window of ours is in front while it's open.
        SetForegroundWindow(owner)
        // The chosen item comes back as a WM_COMMAND to the owner (see runMenuCommand).
        let shown = TrackPopupMenuEx(menu, UINT(TPM_RIGHTBUTTON), p.x, p.y, owner, nil)
        Win32.log("menu of \(items.count) items at \(p.x),\(p.y): \(shown ? "closed" : "failed, error \(GetLastError())")")
        PostMessageW(owner, UINT(WM_NULL), 0, 0)
    }

    func runMenuCommand(_ command: Int) {
        guard command > 0 && command <= menuActions.count else { return }
        let run = menuActions[command - 1]
        menuActions = []
        run()
    }

    private static func build(_ items: [MenuItem], _ actions: inout [() -> Void]) -> HMENU {
        let menu = CreatePopupMenu()!
        for it in items {
            // "&" marks a keyboard shortcut letter in Windows menus.
            let title = Win32.wide(it.title.replacingOccurrences(of: "&", with: "&&"))
            switch it.kind {
            case .separator:
                AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
            case .label:
                AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, title)
            case .action(let run):
                actions.append(run)
                AppendMenuW(menu, UINT(MF_STRING) | (it.checked ? UINT(MF_CHECKED) : 0), UINT_PTR(actions.count), title)
            case .submenu(let children):
                if it.enabled && !children.isEmpty {
                    let sub = build(children, &actions)
                    AppendMenuW(menu, UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: sub)), title)
                } else {
                    AppendMenuW(menu, UINT(MF_STRING | MF_GRAYED), 0, title)
                }
            }
        }
        return menu
    }

    // MARK: App

    private static let runKey = Win32.wide("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
    private static let valueName = Win32.wide("Mochi")
    private static let currentUser = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))   // HKEY_CURRENT_USER

    var opensAtLogin: Bool {
        var size: DWORD = 0
        return RegGetValueW(Self.currentUser, Self.runKey, Self.valueName, DWORD(RRF_RT_REG_SZ), nil, nil, &size) == ERROR_SUCCESS
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    func setOpensAtLogin(_ on: Bool) throws {
        let status: LSTATUS
        if on {
            var path = [WCHAR](repeating: 0, count: 1024)
            let n = Int(GetModuleFileNameW(nil, &path, DWORD(path.count)))
            let command = Win32.wide("\"" + String(decoding: path.prefix(n), as: UTF16.self) + "\"")
            status = command.withUnsafeBytes { bytes in
                RegSetKeyValueW(Self.currentUser, Self.runKey, Self.valueName, DWORD(REG_SZ), bytes.baseAddress, DWORD(bytes.count))
            }
        } else {
            status = RegDeleteKeyValueW(Self.currentUser, Self.runKey, Self.valueName)
        }
        if status != ERROR_SUCCESS { throw Failure(errorDescription: "Windows error \(status).") }
    }

    func showAlert(_ title: String, _ message: String) {
        MessageBoxW(menuOwner, Win32.wide(message), Win32.wide(title), UINT(MB_OK | MB_ICONINFORMATION))
    }

    func quit() { onQuit?() }
}
