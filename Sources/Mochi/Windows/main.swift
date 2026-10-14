import CDirect2D
import Foundation
import WinSDK

// Sharp at any display scaling: we place and draw in real pixels.
SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))   // per-monitor aware, v2
// A windowed app has no console, so with MOCHI_DEBUG the log goes to %TEMP%\mochi-debug.log.
if Cat.debug {
    let log = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-debug.log").path
    var file: UnsafeMutablePointer<FILE>?
    _ = freopen_s(&file, log, "a", stdout)
    // Unbuffered, so nothing is lost if it crashes. (Windows has no line buffering, and rejects
    // _IOLBF without a buffer size.)
    setvbuf(stdout, nil, _IONBF, 0)
}
let win = WinPlatform()
platform = win

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    Sheet.render(to: args[i + 1], coatID: i + 2 < args.count ? args[i + 2] : nil, on: win)
    exit(0)
}
if args.contains("--bench") { Bench.run(on: win); exit(0) }

// One copy at a time; a second would bring a second set of cats.
let instance = CreateMutexW(nil, true, Win32.wide("Local\\MochiDesktopCat"))
if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) { exit(0) }

let app = WinApp(platform: win)
app.run()
_ = instance
