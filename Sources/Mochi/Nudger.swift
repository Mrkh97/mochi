import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Physically wobbles other apps' windows (the cat's weight yanking on them).
/// Needs the Accessibility permission; without it, nothing moves and the cat just bounces.
final class Nudger {
    static let shared = Nudger()
    private let queue = DispatchQueue(label: "mochi.nudge", qos: .userInteractive)
    private var busy = Set<CGWindowID>()
    private let lock = NSLock()

    var enabled = true
    var trusted: Bool { AXIsProcessTrusted() }
    var active: Bool { enabled && trusted }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Damped spring: pulled down by `amplitude` points, then bobbing back into place.
    func jiggle(_ win: WinInfo, amplitude: CGFloat, duration: Double = 0.75) {
        guard active else { return }
        lock.lock()
        if busy.contains(win.id) { lock.unlock(); return }
        busy.insert(win.id)
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); busy.remove(win.id); lock.unlock() }
            guard let el = element(for: win) else {
                if Cat.debug { print("nudge: no AX element for window \(win.id)") }
                return
            }
            if Cat.debug { print("nudge: wobbling window \(win.id) by \(amplitude)pt") }
            AXUIElementSetMessagingTimeout(el, 0.15)
            guard let origin = position(of: el) else { return }
            let start = CACurrentMediaTime()
            var t = 0.0
            while t < duration {
                let offset = amplitude * 1.5 * CGFloat(exp(-5.0 * t) * sin(2 * .pi * 3.0 * t))
                set(el, CGPoint(x: origin.x, y: origin.y + offset.rounded()))
                usleep(16_000)
                t = CACurrentMediaTime() - start
            }
            set(el, origin)
        }
    }

    private func element(for win: WinInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(win.pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return nil }
        for el in list {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(el, &id) == .success, id == win.id { return el }
        }
        // Fall back to matching by position.
        return list.first { el in
            guard let p = position(of: el) else { return false }
            return abs(p.x - win.frame.minX) < 2 && abs(p.y - win.frame.minY) < 2
        }
    }

    private func position(of el: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    private func set(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
        }
    }
}
