import CDirect2D
import Foundation
import WinSDK

/// The app on Windows: a hidden window that owns the tray icon and menus and receives the frame
/// timer and display changes, driving the shared `Household`.
final class WinApp {
    static var shared: WinApp?

    let host: HWND
    private let win: WinPlatform
    private let household = Household()
    private var icons: (normal: HICON?, alert: HICON?) = (nil, nil)
    private var alerting = false
    private let taskbarCreated = RegisterWindowMessageW(Win32.wide("TaskbarCreated"))

    private static let trayMessage = UINT(WM_APP + 1)
    private static let frameTimer: UINT_PTR = 1
    private static let saveTimer: UINT_PTR = 2

    init(platform win: WinPlatform) {
        self.win = win
        host = Win32.createWindow(className: "MochiHost", exStyle: DWORD(WS_EX_TOOLWINDOW), style: DWORD(WS_POPUP))
        win.menuOwner = host
        WinApp.shared = self
    }

    func run() {
        household.start()
        household.onAttentionChanged = { [weak self] alert in
            self?.alerting = alert
            self?.updateTray(adding: false)
        }
        win.onQuit = { [weak self] in
            self?.save()
            PostQuitMessage(0)
        }
        icons = (Self.makeIcon(win, alert: false), Self.makeIcon(win, alert: true))
        updateTray(adding: true)
        // Timers are only as fine as the system clock; ask for 1 ms ticks while we run.
        timeBeginPeriod(1)
        SetTimer(host, Self.frameTimer, 15, nil)
        SetTimer(host, Self.saveTimer, 15_000, nil)

        var msg = MSG()
        while GetMessageW(&msg, nil, 0, 0) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
        KillTimer(host, Self.frameTimer)
        KillTimer(host, Self.saveTimer)
        timeEndPeriod(1)
        removeTray()
    }

    /// Settings only reach the disk on Windows when asked to (macOS writes them by itself).
    private func save() {
        household.saveNeeds()
        UserDefaults.standard.synchronize()
    }

    func handle(_ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch msg {
        case UINT(WM_TIMER) where wParam == Self.saveTimer:
            UserDefaults.standard.synchronize()
            return 0
        case UINT(WM_CLOSE):
            // Asked to close from outside (taskkill, an installer): quit properly, saving first.
            win.quit()
            return 0
        case UINT(WM_QUERYENDSESSION):
            return 1
        case UINT(WM_ENDSESSION):
            // Logging off or shutting down: the process ends without running anything else.
            if wParam != 0 { save() }
            return 0
        case UINT(WM_TIMER) where wParam == Self.frameTimer:
            // Keeps running inside menus' and dialogs' own message loops, so the cats never freeze.
            household.tick()
            win.flushSprites()
            return 0
        case UINT(WM_COMMAND):
            win.runMenuCommand(Int(wParam & 0xFFFF))
            return 0
        case Self.trayMessage:
            let event = Int32(truncatingIfNeeded: lParam & 0xFFFF)
            if event == WM_LBUTTONUP || event == WM_RBUTTONUP {
                win.popUpMenu(household.menu(for: nil))
            }
            return 0
        case UINT(WM_DISPLAYCHANGE), UINT(WM_DPICHANGED), UINT(WM_SETTINGCHANGE):
            // Displays, scaling or the taskbar's size changed.
            win.updateScale()
            household.screensChanged()
            return 0
        case taskbarCreated:
            // Explorer restarted and forgot our icon.
            updateTray(adding: true)
            return 0
        default:
            return nil
        }
    }

    // MARK: Tray

    private func trayData() -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = host
        data.uID = 1
        return data
    }

    private func updateTray(adding: Bool) {
        var data = trayData()
        data.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
        data.uCallbackMessage = Self.trayMessage
        data.hIcon = alerting ? icons.alert : icons.normal
        let tip = Array((alerting ? "Mochi: the cats need something" : "Mochi").utf16.prefix(127)) + [0]
        withUnsafeMutableBytes(of: &data.szTip) { buf in
            tip.withUnsafeBytes { buf.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buf.count))) }
        }
        Shell_NotifyIconW(DWORD(adding ? NIM_ADD : NIM_MODIFY), &data)
    }

    private func removeTray() {
        var data = trayData()
        Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
    }

    /// A small cat face, drawn with the same renderer as everything else.
    private static func makeIcon(_ win: WinPlatform, alert: Bool) -> HICON? {
        let side = Int(GetSystemMetrics(SM_CXSMICON))
        guard side > 0, mg_canvas_begin(win.canvas, Int32(side), Int32(side)) != 0 else { return nil }
        let ctx = CGContext(canvas: win.canvas, width: side, height: side)
        ctx.scaleBy(x: CGFloat(side) / 18, y: CGFloat(side) / 18)
        let coat = Coat.named("ginger")
        let head = CGMutablePath()
        head.addEllipse(in: CGRect(x: 2, y: 2, width: 14, height: 11.5))
        head.move(to: CGPoint(x: 2.6, y: 9)); head.addLine(to: CGPoint(x: 3.6, y: 16.5)); head.addLine(to: CGPoint(x: 8, y: 12)); head.closeSubpath()
        head.move(to: CGPoint(x: 15.4, y: 9)); head.addLine(to: CGPoint(x: 14.4, y: 16.5)); head.addLine(to: CGPoint(x: 10, y: 12)); head.closeSubpath()
        ctx.addPath(head)
        ctx.setFillColor(coat.base)
        ctx.setStrokeColor(coat.outline)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(CatRenderer.eyeDark)
        ctx.fillEllipse(in: CGRect(x: 5.4, y: 6.4, width: 2.2, height: 2.8))
        ctx.fillEllipse(in: CGRect(x: 10.4, y: 6.4, width: 2.2, height: 2.8))
        if alert {
            // A red dot: the cats need something.
            ctx.setFillColor(rgb(0xFF3B30))
            ctx.fillEllipse(in: CGRect(x: 11.5, y: 10.5, width: 7, height: 7))
        }
        guard mg_canvas_end(win.canvas) != 0 else { return nil }

        var stride: Int32 = 0
        guard let pixels = mg_canvas_pixels(win.canvas, &stride) else { return nil }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(side)
        info.bmiHeader.biHeight = -LONG(side)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var bits: UnsafeMutableRawPointer?
        guard let color = CreateDIBSection(nil, &info, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return nil }
        for y in 0..<side {
            (bits + y * side * 4).copyMemory(from: pixels + y * Int(stride), byteCount: side * 4)
        }
        let mask = CreateBitmap(Int32(side), Int32(side), 1, 1, nil)
        var ii = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        let icon = CreateIconIndirect(&ii)
        DeleteObject(color)
        DeleteObject(mask)
        return icon
    }
}
