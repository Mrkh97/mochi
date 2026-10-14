import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let household = Household()
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Keep animating smoothly even when another app is in front.
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Cat on the loose")

        household.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        household.onAttentionChanged = { [weak self] alert in
            self?.statusItem.button?.image = Self.menuIcon(alert: alert)
        }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.household.screensChanged()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            World.shared.refresh()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.household.saveNeeds()
        }

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.household.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func menuNeedsUpdate(_ menu: NSMenu) { MenuBuilder.fill(menu, with: household.menu(for: nil)) }

    // MARK: Icon

    static func menuIcon(alert: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor((alert ? NSColor.labelColor : NSColor.black).cgColor)
            let head = CGMutablePath()
            head.addEllipse(in: CGRect(x: 2, y: 2, width: 14, height: 11.5))
            head.move(to: CGPoint(x: 2.6, y: 9)); head.addLine(to: CGPoint(x: 3.6, y: 16.5)); head.addLine(to: CGPoint(x: 8, y: 12)); head.closeSubpath()
            head.move(to: CGPoint(x: 15.4, y: 9)); head.addLine(to: CGPoint(x: 14.4, y: 16.5)); head.addLine(to: CGPoint(x: 10, y: 12)); head.closeSubpath()
            ctx.addPath(head)
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: 5.4, y: 6.4, width: 2.2, height: 2.8))
            ctx.fillEllipse(in: CGRect(x: 10.4, y: 6.4, width: 2.2, height: 2.8))
            if alert {
                // A red dot: the cats need something.
                ctx.setBlendMode(.normal)
                ctx.setFillColor(NSColor.systemRed.cgColor)
                ctx.fillEllipse(in: CGRect(x: 12.5, y: 11.5, width: 6, height: 6))
            }
            return true
        }
        img.isTemplate = !alert
        return img
    }
}
