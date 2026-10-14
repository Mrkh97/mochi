import Foundation

/// The running app, minus the operating system: the cats, their box, bowls and toy, the frame loop,
/// settings, and what the menu offers. The platform layer drives `tick()` about 60 times a second
/// and shows `menu(for:)` from the menu bar, the tray, or a right-click on a cat.
final class Household {
    private(set) var home: HomeBox!
    private(set) var bowls: Bowls!
    private(set) var toy: Toy!
    private(set) var cats: [Cat] = [] { didSet { Den.shared.cats = cats } }
    private var slowClock: CGFloat = 0
    private var saveClock: CGFloat = 0
    private(set) var alerting = false
    private var last = platform.now()
    private var worldClock: CGFloat = 1
    private var lastMouse = CGPoint.zero
    private var mouseSpeed: CGFloat = 0
    private let defaults = UserDefaults.standard
    private static let names = ["Mochi", "Tofu", "Biscuit", "Miso", "Pudding", "Noodle", "Dumpling"]

    /// Called when the cats start or stop needing something (empty bowls, a grumpy cat).
    var onAttentionChanged: ((Bool) -> Void)?

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
    private(set) var paused = false

    func start() {
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
    }

    // MARK: Loop

    func tick() {
        let now = platform.now()
        defer { Perf.add("tick", platform.now() - now) }
        let dt = CGFloat(min(0.05, now - last))
        last = now
        guard !paused else { return }
        worldClock += dt
        // Re-read the window list often only while some cat is on the move.
        let busy = cats.contains { $0.isMoving }
        if worldClock > (busy ? 1.0 / 10 : 1.0 / 4) {
            worldClock = 0
            let r0 = platform.now()
            World.shared.refresh()
            cats.forEach { $0.verifyStack() }
            Perf.add("refresh", platform.now() - r0)
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
            updateAttention()
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
        c.onContextMenu = { [weak self, weak c] in
            guard let self else { return }
            platform.popUpMenu(self.menu(for: c))
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

    func screensChanged() {
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

    func saveNeeds() {
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

    private func updateAttention() {
        let a = needsAttention
        if a != alerting {
            alerting = a
            onAttentionChanged?(a)
        }
    }

    private func dropToy() {
        let f = bowls.frameCG
        toy.show(at: CGPoint(x: f.minX - 30 * scale, y: f.minY - 80 * scale))
        defaults.set(true, forKey: "toyOut")
    }

    private func refillAll() {
        bowls.refill(drink: false)
        bowls.refill(drink: true)
    }

    private func toggleToy() {
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

    /// The menu; right-clicking a cat adds a few things just for that cat at the top.
    func menu(for cat: Cat?) -> [MenuItem] {
        var items: [MenuItem] = []
        if let cat, cats.count > 1 {
            items.append(.action("Rehome \(cat.name)") { [weak self, weak cat] in
                if let cat { self?.rehome(cat) }
            })
            items.append(.separator)
        }
        for c in cats {
            var text = "\(c.name): \(c.status)"
            if let note = c.needsNote { text += " (\(note))" }
            items.append(.label(text))
        }
        items.append(.label("Food \(meter(bowls.food))   Water \(meter(bowls.water))"))
        items.append(.separator)
        items.append(.action("Refill Food & Water", key: "f") { [weak self] in self?.refillAll() })
        items.append(.action(toy.visible ? "Put the Yarn Ball Away" : "Get the Yarn Ball Out", key: "y") { [weak self] in self?.toggleToy() })
        items.append(.separator)
        items.append(.action("Call Home", key: "h") { [weak self] in self?.callHome() })
        items.append(.action("Nap Time") { [weak self] in self?.napTime() })
        items.append(.action("Wake Up!") { [weak self] in self?.wakeUp() })
        items.append(.separator)

        func coatItems(_ i: Int) -> [MenuItem] {
            Coat.all.map { coat in
                .action(coat.name, checked: cats[i].coat.id == coat.id) { [weak self] in self?.setCoat(i, coat.id) }
            }
        }
        if cats.count == 1 {
            items.append(.submenu("Coat", coatItems(0)))
        } else {
            items.append(.submenu("Coat", cats.indices.map { .submenu(cats[$0].name, coatItems($0)) }))
        }

        items.append(.submenu("Size", [("Small", 0.75), ("Medium", 1.0), ("Large", 1.3), ("Chonky", 1.6)].map { name, v in
            .action(name, checked: abs(scale - v) < 0.01) { [weak self] in self?.setSize(v) }
        }))
        items.append(.submenu("Energy", [("Sleepy", 0.6), ("Normal", 1.0), ("Playful", 1.5)].map { name, v in
            .action(name, checked: abs(activity - v) < 0.01) { [weak self] in self?.setActivity(v) }
        }))

        let canAdopt = cats.count < 6
        items.append(.submenu("Adopt Another Cat", enabled: canAdopt, !canAdopt ? [] : Coat.all.map { coat in
            .action(coat.name) { [weak self] in self?.adopt(coat.id) }
        }))
        let canRehome = cats.count > 1
        items.append(.submenu("Rehome a Cat", enabled: canRehome, !canRehome ? [] : cats.map { c in
            .action("\(c.name) (\(c.coat.name))") { [weak self, weak c] in
                if let c { self?.rehome(c) }
            }
        }))
        items.append(.separator)

        items.append(.action("Box Stays Above Windows", checked: home.floating) { [weak self] in self?.toggleBoxFloating() })
        items.append(.action("Move Box to Pointer") { [weak self] in self?.moveBoxToPointer() })
        let nudgeTitle = Nudger.shared.trusted ? "Slips Wobble Real Windows" : "Slips Wobble Real Windows (needs Accessibility)…"
        items.append(.action(nudgeTitle, checked: Nudger.shared.active) { [weak self] in self?.toggleNudge() })
        items.append(.action("Open at Login", checked: platform.opensAtLogin) { Self.toggleLogin() })
        items.append(.separator)
        items.append(.action(paused ? "Resume" : "Hide Cats", key: "p") { [weak self] in self?.togglePause() })
        items.append(.action("Quit Mochi", key: "q") { platform.quit() })
        return items
    }

    private func callHome() {
        for c in cats where c.surface != .box {
            c.ask(.home)
            c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
        }
    }

    private func napTime() {
        for c in cats where !c.isAsleep { c.ask(.nap) }
    }

    private func wakeUp() {
        for c in cats {
            c.energy = max(c.energy, 0.9)
            if c.isAsleep {
                c.interrupt(with: [c.surface == .box ? BoxIdle(2) : Stretch()])
                c.spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
            }
        }
    }

    private func setCoat(_ i: Int, _ id: String) {
        guard i < cats.count else { return }
        cats[i].coat = Coat.named(id)
        saveCats()
    }

    private func setSize(_ v: Double) {
        scale = CGFloat(v)
        home.setScale(scale)
        bowls.setScale(scale)
        toy.setScale(scale)
        for c in cats {
            c.setScale(scale)
            if c.surface == .box { c.stand(on: home.surface, x: (home.surface.minX + home.surface.maxX) / 2) }
        }
    }

    private func setActivity(_ v: Double) {
        activity = CGFloat(v)
        cats.forEach { $0.activity = activity }
    }

    private func adopt(_ coatID: String) {
        guard cats.count < 6 else { return }
        addCat(coat: Coat.named(coatID), index: cats.count)
        cats.last?.queue = [Sleep(1.5)]
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
        c.sprite.fadeOut()
    }

    private func toggleBoxFloating() {
        home.floating.toggle()
        bowls.floating = home.floating
        defaults.set(home.floating, forKey: "boxFloating")
        cats.filter { $0.depth == .atBowls }.forEach { $0.applyDepth() }
        cats.filter { $0.depth == .inBox || $0.depth == .onBox }.forEach { $0.applyDepth() }
    }

    private func moveBoxToPointer() {
        home.move(rimTo: Coords.mouse)
        for c in cats where c.surface == .box { c.stand(on: home.surface, x: (home.surface.minX + home.surface.maxX) / 2) }
    }

    private func toggleNudge() {
        if !Nudger.shared.trusted {
            Nudger.shared.enabled = true
            Nudger.shared.requestPermission()
        } else {
            Nudger.shared.enabled.toggle()
        }
        defaults.set(Nudger.shared.enabled, forKey: "nudge")
    }

    private static func toggleLogin() {
        do {
            try platform.setOpensAtLogin(!platform.opensAtLogin)
        } catch {
            platform.showAlert("Couldn't change the login item", error.localizedDescription)
        }
    }

    private func togglePause() {
        paused.toggle()
        for c in cats {
            c.paused = paused
            if paused { c.sprite.orderOut() } else { c.show() }
        }
        if paused {
            home.hide()
            bowls.hide()
            toy.sprite.orderOut()
        } else {
            home.show()
            bowls.show()
            if toy.visible { toy.sprite.orderFront() }
            cats.forEach { $0.applyDepth() }
        }
    }
}

/// Physically wobbles other apps' windows (the cat's weight yanking on them), when allowed.
final class Nudger {
    static let shared = Nudger()
    var enabled = true
    var trusted: Bool { platform.canMoveWindows }
    var active: Bool { enabled && trusted }

    func requestPermission() { platform.requestWindowAccess() }

    func jiggle(_ win: WinInfo, amplitude: CGFloat) {
        guard active else { return }
        platform.jiggle(win, amplitude: amplitude)
    }
}

/// Debug timing (MOCHI_DEBUG): prints average cost per call every few seconds.
enum Perf {
    static var sums: [String: (Double, Int)] = [:]
    static var lastPrint = 0.0
    static func add(_ key: String, _ dt: Double) {
        guard Cat.debug else { return }
        let v = sums[key] ?? (0, 0)
        sums[key] = (v.0 + dt, v.1 + 1)
        let now = platform.now()
        if lastPrint == 0 { lastPrint = now }
        if now - lastPrint > 5 {
            let span = now - lastPrint
            let line = sums.map { "\($0.key) " + String(format: "%.3fms x%.0f/s", $0.value.0 / Double($0.value.1) * 1000, Double($0.value.1) / span) }.sorted().joined(separator: "  ")
            print("perf:", line)
            sums = [:]
            lastPrint = now
        }
    }
}
