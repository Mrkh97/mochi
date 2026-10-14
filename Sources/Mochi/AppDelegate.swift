import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var home: HomeBox!
    private var bowls: Bowls!
    private var toy: Toy!
    private(set) var cats: [Cat] = [] { didSet { Den.shared.cats = cats } }
    private var slowClock: CGFloat = 0
    private var saveClock: CGFloat = 0
    private var alerting = false
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var worldClock: CGFloat = 1
    private var lastMouse = CGPoint.zero
    private var mouseSpeed: CGFloat = 0
    private var activityToken: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private static let names = ["Mochi", "Tofu", "Biscuit", "Miso", "Pudding", "Noodle", "Dumpling"]

    private var scale: CGFloat {
        get { CGFloat(defaults.object(forKey: "scale") as? Double ?? 1.0) }
        set { defaults.set(Double(newValue), forKey: "scale") }
    }
    private var activity: CGFloat {
        get { CGFloat(defaults.object(forKey: "activity") as? Double ?? 1.0) }
        set { defaults.set(Double(newValue), forKey: "activity") }
    }
    private var coats: [String] {
        get { defaults.stringArray(forKey: "coats") ?? ["ginger"] }
        set { defaults.set(newValue, forKey: "coats") }
    }
    private var catNames: [String] {
        get { defaults.stringArray(forKey: "names") ?? [] }
        set { defaults.set(newValue, forKey: "names") }
    }
    private var paused = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Keep animating smoothly even when another app is in front.
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Cat on the loose")
        Nudger.shared.enabled = defaults.object(forKey: "nudge") as? Bool ?? true

        World.shared.refreshScreens()
        World.shared.refresh()
        home = HomeBox(scale: scale, originCG: .zero)
        home.floating = defaults.object(forKey: "boxFloating") as? Bool ?? true
        home.move(rimTo: savedRim())
        home.onMoved = { [weak self] in self?.saveRim() }
        home.show()
        Den.shared.home = home

        // Food and water sit on the floor to the left of the box, unless you've moved them.
        let floorY = World.shared.screen(at: home.rim).floorY
        bowls = Bowls(scale: scale, defaultBottomRight: CGPoint(x: home.frameCG.minX - 4, y: floorY + 4 * scale))
        bowls.floating = home.floating
        bowls.show()
        Den.shared.bowls = bowls
        if ProcessInfo.processInfo.environment["MOCHI_EMPTY"] != nil {
            bowls.consume(1, drink: false)
            bowls.consume(1, drink: true)
        }

        toy = Toy(scale: scale)
        Den.shared.toy = toy
        if defaults.object(forKey: "toyOut") as? Bool ?? true { dropToy() }

        let names = catNames
        for (i, id) in coats.enumerated() { addCat(coat: Coat.named(id), name: i < names.count ? names[i] : nil, index: i, persist: false) }
        catNames = cats.map { $0.name }
        loadNeeds()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            World.shared.refresh()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveNeeds()
        }

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Loop

    private func tick() {
        let now = CACurrentMediaTime()
        defer { Perf.add("tick", CACurrentMediaTime() - now) }
        let dt = CGFloat(min(0.05, now - last))
        last = now
        guard !paused else { return }
        worldClock += dt
        // Re-read the window list often only while some cat is on the move.
        let busy = cats.contains { $0.isMoving }
        if worldClock > (busy ? 1.0 / 10 : 1.0 / 4) {
            worldClock = 0
            let r0 = CACurrentMediaTime()
            World.shared.refresh()
            cats.forEach { $0.verifyStack() }
            Perf.add("refresh", CACurrentMediaTime() - r0)
        }
        let m = Coords.mouse
        let sp = hypot(m.x - lastMouse.x, m.y - lastMouse.y) / max(dt, 0.001)
        mouseSpeed += (sp - mouseSpeed) * 0.3
        lastMouse = m
        toy.update(dt)
        bowls.update(dt)
        for c in cats {
            c.frameDebt += dt
            // Skip frames the cat doesn't need, but react to the pointer immediately.
            let step = 1 / c.desiredFPS - 0.004
            guard c.frameDebt >= step || c.contains(m) else { continue }
            let cdt = c.frameDebt
            c.update(cdt)
            c.frameDebt = 0
            c.considerPlay(mouseSpeed)
            c.considerToy(cdt)
            c.considerMood()
        }
        home.updateMouse(m)
        bowls.updateMouse(m)

        slowClock += dt
        if slowClock > 1 {
            slowClock = 0
            updateBadge()
            if let s = ProcessInfo.processInfo.environment["MOCHI_REFILL_AFTER"], let after = Double(s),
               cats.first.map({ Double($0.time) > after && Double($0.time) < after + 1.2 }) == true {
                refillAll()
            }
            if ProcessInfo.processInfo.environment["MOCHI_TOSS"] != nil && toy.visible && toy.restingFor > 2.5 {
                // Test mode plays fetch with itself.
                toy.toss(CGPoint(x: .random(in: -700...700), y: .random(in: -1000 ... -500)))
            }
        }
        saveClock += dt
        if saveClock > 15 { saveClock = 0; saveNeeds() }
    }

    // MARK: Cats

    /// The first name nobody is using yet.
    private func freeName() -> String {
        Self.names.first { n in !cats.contains { $0.name == n } } ?? "Kitty \(cats.count + 1)"
    }

    private func addCat(coat: Coat, name: String? = nil, index: Int, persist: Bool = true) {
        let c = Cat(name: name ?? freeName(), coat: coat, scale: scale, home: home)
        c.activity = activity
        c.view.onContextMenu = { [weak self, weak c] event, view in
            guard let self else { return }
            let menu = NSMenu()
            self.build(menu, for: c)
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
        // Everyone starts asleep in the box.
        let rim = home.surface
        c.stand(on: rim, x: (rim.minX + rim.maxX) / 2 + CGFloat(index) * 6 - 6)
        c.depth = .inBox
        c.target = .peek(rise: 1)
        c.pose = c.target
        c.snapTurn()
        c.queue = [Sleep(.random(in: 3...6) + CGFloat(index) * 2)]
        c.lastSocial = -CGFloat.random(in: 0...10)
        cats.append(c)
        c.show()
        if persist { saveCats() }
    }

    private func saveCats() {
        coats = cats.map { $0.coat.id }
        catNames = cats.map { $0.name }
        saveNeeds()
    }

    private func screensChanged() {
        World.shared.refreshScreens()
        World.shared.refresh()
        if !World.shared.screens.contains(where: { $0.frame.contains(home.rim) }) { home.move(rimTo: defaultRim()) }
        for c in cats where c.surface != nil {
            if c.currentSurface == nil || World.shared.screens.allSatisfy({ !$0.frame.insetBy(dx: -40, dy: -40).contains(c.pos) }) {
                c.pos = CGPoint(x: home.rim.x, y: home.rim.y - 80)
                c.interrupt(with: [Fall()])
            }
        }
    }

    // MARK: Home position

    private func defaultRim() -> CGPoint {
        let s = World.shared.screens.first ?? ScreenInfo(frame: .zero, visible: CGRect(x: 0, y: 0, width: 1440, height: 900))
        return CGPoint(x: s.visible.maxX - 110 * scale, y: s.floorY - 54 * scale)
    }

    private func savedRim() -> CGPoint {
        if let a = defaults.array(forKey: "boxRim") as? [Double], a.count == 2 {
            let p = CGPoint(x: a[0], y: a[1])
            if World.shared.screens.contains(where: { $0.frame.contains(p) }) { return p }
        }
        return defaultRim()
    }

    private func saveRim() { defaults.set([Double(home.rim.x), Double(home.rim.y)], forKey: "boxRim") }

    // MARK: Needs, bowls and the toy

    private func saveNeeds() {
        defaults.set(cats.map { [Double($0.hunger), Double($0.thirst), Double($0.grumpy)] }, forKey: "needs")
        defaults.set(Date().timeIntervalSince1970, forKey: "needsSavedAt")
    }

    /// Cats get a bit hungrier while Mochi isn't running (up to 20 minutes' worth).
    private func loadNeeds() {
        guard let arr = defaults.array(forKey: "needs") as? [[Double]] else { return }
        let away = CGFloat(min(20 * 60, max(0, Date().timeIntervalSince1970 - defaults.double(forKey: "needsSavedAt"))))
        for (c, n) in zip(cats, arr) where n.count == 3 {
            c.hunger = min(1, CGFloat(n[0]) + away / (25 * 60))
            c.thirst = min(1, CGFloat(n[1]) + away / (18 * 60))
            c.grumpy = CGFloat(n[2])
        }
    }

    private var needsAttention: Bool {
        bowls.food < 0.03 || bowls.water < 0.03 || cats.contains { $0.grumpy > 0.5 }
    }

    private func updateBadge() {
        let a = needsAttention
        if a != alerting {
            alerting = a
            statusItem.button?.image = Self.menuIcon(alert: a)
        }
    }

    private func dropToy() {
        let f = bowls.frameCG
        toy.show(at: CGPoint(x: f.minX - 30 * scale, y: f.minY - 80 * scale))
        defaults.set(true, forKey: "toyOut")
    }

    @objc private func refillAll() {
        bowls.refill(drink: false)
        bowls.refill(drink: true)
    }

    @objc private func toggleToy() {
        if toy.visible {
            toy.hide()
            defaults.set(false, forKey: "toyOut")
        } else {
            dropToy()
        }
    }

    private func meter(_ v: CGFloat) -> String {
        let n = Int((v * 5).rounded(.up))
        return String(repeating: "●", count: n) + String(repeating: "○", count: 5 - n)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) { build(menu, for: nil) }

    private func item(_ title: String, _ action: Selector?, key: String = "", on: Bool = false, tag: Int = 0, rep: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        i.tag = tag
        i.representedObject = rep
        return i
    }

    /// The menu; right-clicking a cat adds a few things just for that cat at the top.
    private func build(_ menu: NSMenu, for cat: Cat?) {
        menu.removeAllItems()
        if let cat, cats.count > 1 {
            menu.addItem(item("Rehome \(cat.name)", #selector(rehomeItem(_:)), rep: cat))
            menu.addItem(.separator())
        }
        for c in cats {
            var text = "\(c.name): \(c.status)"
            if let note = c.needsNote { text += " (\(note))" }
            let line = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        let levels = NSMenuItem(title: "Food \(meter(bowls.food))   Water \(meter(bowls.water))", action: nil, keyEquivalent: "")
        levels.isEnabled = false
        menu.addItem(levels)
        menu.addItem(.separator())
        menu.addItem(item("Refill Food & Water", #selector(refillAll), key: "f"))
        menu.addItem(item(toy.visible ? "Put the Yarn Ball Away" : "Get the Yarn Ball Out", #selector(toggleToy), key: "y"))
        menu.addItem(.separator())
        menu.addItem(item("Call Home", #selector(callHome), key: "h"))
        menu.addItem(item("Nap Time", #selector(napTime)))
        menu.addItem(item("Wake Up!", #selector(wakeUp)))
        menu.addItem(.separator())

        let coatMenu = NSMenu()
        if cats.count == 1 {
            for coat in Coat.all {
                coatMenu.addItem(item(coat.name, #selector(setCoat(_:)), on: cats[0].coat.id == coat.id, rep: "0|\(coat.id)"))
            }
        } else {
            for (i, c) in cats.enumerated() {
                let sub = NSMenu()
                for coat in Coat.all { sub.addItem(item(coat.name, #selector(setCoat(_:)), on: c.coat.id == coat.id, rep: "\(i)|\(coat.id)")) }
                let ci = NSMenuItem(title: c.name, action: nil, keyEquivalent: "")
                ci.submenu = sub
                coatMenu.addItem(ci)
            }
        }
        let coatItem = NSMenuItem(title: "Coat", action: nil, keyEquivalent: "")
        coatItem.submenu = coatMenu
        menu.addItem(coatItem)

        let sizeMenu = NSMenu()
        for (name, v) in [("Small", 0.75), ("Medium", 1.0), ("Large", 1.3), ("Chonky", 1.6)] {
            sizeMenu.addItem(item(name, #selector(setSize(_:)), on: abs(scale - v) < 0.01, rep: v))
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let actMenu = NSMenu()
        for (name, v) in [("Sleepy", 0.6), ("Normal", 1.0), ("Playful", 1.5)] {
            actMenu.addItem(item(name, #selector(setActivity(_:)), on: abs(activity - v) < 0.01, rep: v))
        }
        let actItem = NSMenuItem(title: "Energy", action: nil, keyEquivalent: "")
        actItem.submenu = actMenu
        menu.addItem(actItem)

        let addMenu = NSMenu()
        for coat in Coat.all { addMenu.addItem(item(coat.name, #selector(addCatItem(_:)), rep: coat.id)) }
        let addItem = NSMenuItem(title: "Adopt Another Cat", action: cats.count < 6 ? #selector(noop) : nil, keyEquivalent: "")
        addItem.target = self
        addItem.submenu = cats.count < 6 ? addMenu : nil
        menu.addItem(addItem)
        let rehomeMenu = NSMenu()
        for c in cats { rehomeMenu.addItem(item("\(c.name) (\(c.coat.name))", #selector(rehomeItem(_:)), rep: c)) }
        let rehome = NSMenuItem(title: "Rehome a Cat", action: cats.count > 1 ? #selector(noop) : nil, keyEquivalent: "")
        rehome.target = self
        rehome.submenu = cats.count > 1 ? rehomeMenu : nil
        menu.addItem(rehome)
        menu.addItem(.separator())

        menu.addItem(item("Box Stays Above Windows", #selector(toggleBoxFloating), on: home.floating))
        menu.addItem(item("Move Box to Pointer", #selector(moveBoxToPointer)))
        let nudgeTitle = Nudger.shared.trusted ? "Slips Wobble Real Windows" : "Slips Wobble Real Windows (needs Accessibility)…"
        menu.addItem(item(nudgeTitle, #selector(toggleNudge), on: Nudger.shared.active))
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item(paused ? "Resume" : "Hide Cats", #selector(togglePause), key: "p"))
        menu.addItem(item("Quit Mochi", #selector(quit), key: "q"))
    }

    @objc private func noop() {}

    @objc private func callHome() {
        for c in cats where c.surface != .box {
            c.ask(.home)
            c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
        }
    }

    @objc private func napTime() {
        for c in cats where !c.isAsleep { c.ask(.nap) }
    }

    @objc private func wakeUp() {
        for c in cats {
            c.energy = max(c.energy, 0.9)
            if c.isAsleep {
                c.interrupt(with: [c.surface == .box ? BoxIdle(2) : Stretch()])
                c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
            }
        }
    }

    @objc private func setCoat(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject as? String else { return }
        let parts = rep.split(separator: "|")
        guard parts.count == 2, let i = Int(parts[0]), i < cats.count else { return }
        cats[i].coat = Coat.named(String(parts[1]))
        saveCats()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        scale = CGFloat(v)
        home.setScale(scale)
        bowls.setScale(scale)
        toy.setScale(scale)
        for c in cats {
            c.setScale(scale)
            if c.surface == .box { c.stand(on: home.surface, x: (home.surface.minX + home.surface.maxX) / 2) }
        }
    }

    @objc private func setActivity(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        activity = CGFloat(v)
        cats.forEach { $0.activity = activity }
    }

    @objc private func addCatItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, cats.count < 6 else { return }
        addCat(coat: Coat.named(id), index: cats.count)
        cats.last?.queue = [Sleep(1.5)]
    }

    @objc private func rehomeItem(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? Cat else { return }
        rehome(c)
    }

    /// Say goodbye to one cat. The others carry on; anyone playing with it simply finds it gone.
    private func rehome(_ c: Cat) {
        guard cats.count > 1, let i = cats.firstIndex(where: { $0 === c }) else { return }
        cats.remove(at: i)
        c.action?.end(c)
        c.action = nil
        c.queue = []
        c.surface = nil
        c.overlay = nil
        if toy.holder === c { toy.release(v: CGPoint(x: 0, y: -150)) }
        saveCats()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            c.panel.animator().alphaValue = 0
        }, completionHandler: {
            c.panel.orderOut(nil)
        })
    }

    @objc private func toggleBoxFloating() {
        home.floating.toggle()
        bowls.floating = home.floating
        defaults.set(home.floating, forKey: "boxFloating")
        cats.filter { $0.depth == .atBowls }.forEach { $0.applyDepth() }
        cats.filter { $0.depth == .inBox || $0.depth == .onBox }.forEach { $0.applyDepth() }
    }

    @objc private func moveBoxToPointer() {
        home.move(rimTo: Coords.mouse)
        for c in cats where c.surface == .box { c.stand(on: home.surface, x: (home.surface.minX + home.surface.maxX) / 2) }
    }

    @objc private func toggleNudge() {
        if !Nudger.shared.trusted {
            Nudger.shared.enabled = true
            Nudger.shared.requestPermission()
        } else {
            Nudger.shared.enabled.toggle()
        }
        defaults.set(Nudger.shared.enabled, forKey: "nudge")
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login item"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        for c in cats {
            c.paused = paused
            if paused { c.panel.orderOut(nil) } else { c.show() }
        }
        if paused {
            home.hide()
            bowls.hide()
            toy.panel.orderOut(nil)
        } else {
            home.show()
            bowls.show()
            if toy.visible { toy.panel.orderFrontRegardless() }
            cats.forEach { $0.applyDepth() }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

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
