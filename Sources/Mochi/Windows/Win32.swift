import Foundation
import WinSDK

/// Bits of Win32 that Swift can't import directly (pointer-valued macros) or that several files need.
enum Win32 {
    // SetWindowPos insert-after values.
    static let top: HWND? = nil
    static let bottom = HWND(bitPattern: 1)
    static let topmost = HWND(bitPattern: -1)
    static let notTopmost = HWND(bitPattern: -2)

    static func key(_ h: HWND) -> UInt { UInt(bitPattern: h) }

    /// Window handles are 32-bit values even in 64-bit processes, so they fit a CGWindowID.
    static func id(_ h: HWND) -> CGWindowID { CGWindowID(truncatingIfNeeded: UInt(bitPattern: h)) }
    /// Handles are sign-extended when widened back.
    static func hwnd(_ id: CGWindowID) -> HWND? { HWND(bitPattern: Int(Int32(bitPattern: id))) }

    static func isTopmost(_ h: HWND) -> Bool {
        GetWindowLongPtrW(h, GWL_EXSTYLE) & LONG_PTR(WS_EX_TOPMOST) != 0
    }

    /// Whichever of `windows` is furthest back.
    static func lowest(_ windows: [HWND]) -> HWND? {
        guard !windows.isEmpty else { return nil }
        let wanted = Set(windows.map(key))
        var found: HWND?
        var h = GetTopWindow(nil)
        var guardCount = 0
        while let w = h, guardCount < 20_000 {
            if wanted.contains(key(w)) { found = w }
            h = GetWindow(w, UINT(GW_HWNDNEXT))
            guardCount += 1
        }
        return found
    }

    static func className(_ h: HWND) -> String {
        var buf = [WCHAR](repeating: 0, count: 64)
        let n = GetClassNameW(h, &buf, Int32(buf.count))
        return String(decoding: buf.prefix(Int(max(0, n))), as: UTF16.self)
    }

    static func wide(_ s: String) -> [WCHAR] { Array(s.utf16) + [0] }

    /// With MOCHI_DEBUG set, a line in the debug log (see main.swift).
    static func log(_ line: @autoclosure () -> String) {
        guard Cat.debug else { return }
        print(String(format: "%.3f ", platform.now()) + line())
    }

    /// One window procedure for all of ours; it hands messages to the sprite or the app they belong to.
    private static let procedure: WNDPROC = { hwnd, msg, wParam, lParam in
        if let hwnd {
            if let sprite = WinSprite.sprite(for: hwnd), let r = sprite.handle(msg, wParam) { return r }
            if let app = WinApp.shared, hwnd == app.host, let r = app.handle(msg, wParam, lParam) { return r }
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }

    private static var registered = Set<String>()

    static func createWindow(className: String, exStyle: DWORD, style: DWORD) -> HWND {
        let instance = GetModuleHandleW(nil)
        let name = wide(className)
        if !registered.contains(className) {
            registered.insert(className)
            name.withUnsafeBufferPointer { n in
                var wc = WNDCLASSEXW()
                wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                wc.lpfnWndProc = procedure
                wc.hInstance = instance
                wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))   // IDC_ARROW
                wc.lpszClassName = n.baseAddress
                RegisterClassExW(&wc)
            }
        }
        return name.withUnsafeBufferPointer { n in
            CreateWindowExW(exStyle, n.baseAddress, n.baseAddress, style, 0, 0, 1, 1, nil, nil, instance, nil)!
        }
    }
}
