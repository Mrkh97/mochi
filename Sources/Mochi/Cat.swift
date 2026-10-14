import Foundation

/// One cat: its window, body, position in the world and current activity.
final class Cat: SpriteContent {
    var name: String
    var coat: Coat
    private(set) var scale: CGFloat
    let sprite: Sprite
    /// The contact point inside the sprite, in its points (y up).
    private(set) var anchor: CGPoint
    let effects = Effects()
    unowned let home: HomeBox
    var activity: CGFloat = 1          // 0.6 sleepy … 1.6 playful

    // Where it is
    var pos = CGPoint.zero             // contact point, CG global coords
    var facing: CGFloat = 1
    var surface: SurfaceRef?           // what it stands on (nil while airborne / carried)
    var attach: SurfaceRef? { didSet { if attach != oldValue { attachFrame = nil } } }
    private var attachFrame: CGRect?
    var depth: Depth = .inBox { didSet { if depth != oldValue { applyDepth() } } }
    private var appliedDepth: Depth?

    // How it looks
    var pose = Pose()
    var target = Pose()
    private(set) var displayPose = Pose()
    var blendRate: CGFloat = 12
    var time: CGFloat = 0
    private(set) var shownView: ViewKind = .side
    private var shownFacing: CGFloat = 1
    private var turnT: CGFloat?
    var allowBlink = true
    var lookAtCursor = true
    private var blinkClock: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var twitchClock: CGFloat = 4
    private var twitchT: CGFloat = -1
    private var wobble: CGFloat = 0

    // What it's doing
    var action: Act?
    var queue: [Act] = []
    var energy: CGFloat = 0.85
    var hostShake: CGFloat = 0
    var lastPlay: CGFloat = -30
    var paused = false

    // Needs and moods (0...1)
    var hunger: CGFloat = .random(in: 0.1...0.3)
    var thirst: CGFloat = .random(in: 0.1...0.3)
    var grumpy: CGFloat = 0
    var lastComplain: CGFloat = -100
    var lastToyChase: CGFloat = -100
    var lastSocial: CGFloat = -100
    var lastHiss: CGFloat = -100
    var walkPhase: CGFloat = 0

    /// Drawn instead of the cat: a scuffle with a friend, or nothing (the friend is inside the cloud).
    enum Overlay { case fight(Coat), hidden }
    var overlay: Overlay?

    // Mouse
    private var press: CGPoint?
    private(set) var dragging = false
    var onContextMenu: (() -> Void)?

    static let testMode = ProcessInfo.processInfo.environment["MOCHI_TEST"] != nil
    static let debug = ProcessInfo.processInfo.environment["MOCHI_DEBUG"] != nil
    static let travelTest = ProcessInfo.processInfo.environment["MOCHI_TRAVEL"] != nil
    static let viewSize = CGSize(width: 230, height: 250)
    static let anchor = CGPoint(x: 115, y: 108)

    init(name: String, coat: Coat, scale: CGFloat, home: HomeBox) {
        self.name = name
        self.coat = coat
        self.scale = scale
        self.home = home
        sprite = platform.makeSprite(size: CGSize(width: Cat.viewSize.width * scale, height: Cat.viewSize.height * scale))
        anchor = CGPoint(x: Cat.anchor.x * scale, y: Cat.anchor.y * scale)
        energy = .random(in: 0.7...0.95)
        sprite.content = self
    }

    func setScale(_ s: CGFloat) {
        scale = s
        sprite.size = CGSize(width: Cat.viewSize.width * s, height: Cat.viewSize.height * s)
        anchor = CGPoint(x: Cat.anchor.x * s, y: Cat.anchor.y * s)
    }

    var world: World { World.shared }
    var z: Double { world.z(of: depth) }
    var screenIndex: Int { world.screenIndex(at: pos) }
    var currentSurface: Surface? { surface.flatMap { world.surface($0) } }
    var status: String { paused ? "Paused" : (action?.status ?? "Thinking…") }
    /// Frames per second this cat currently needs (sleeping cats don't need 60).
    var desiredFPS: CGFloat {
        if dragging || effects.items.count > 0 && !(action is Sleep) { return 60 }
        switch action {
        case is Sleep: return 20
        case is Idle, is Groom, is BoxIdle, is Petted, is Stretch, is Eat, is Sulk, is Complain,
             is PlayWithToy, is Boop, is GroomFriend, is BeGroomed, is Land: return 30
        case let w as Walk: return w.speed > 150 ? 60 : 30
        case is ChaseToy, is Approach, is Flee, is ChaseFriend: return 45
        default: return 60
        }
    }
    var frameDebt: CGFloat = 0
    var hostMovedAt: CGFloat = -10
    private var syncCounter = 0
    var isMoving: Bool {
        switch action {
        case is Walk, is Jump, is Fall, is Climb, is HopOff, is Held, is Slip, is ChaseToy, is Pounce, is Approach, is ChaseFriend: return true
        default: return false
        }
    }
    var hiddenSince: CGFloat?
    var isAsleep: Bool { action is Sleep }

    // MARK: - Frame update

    func update(_ dt: CGFloat) {
        time += dt
        hostShake *= exp(-6 * dt)
        let tSync = platform.now()
        defer { Perf.add("update", platform.now() - tSync) }
        if !isAsleep { energy = max(0, energy - dt / (420 * max(0.6, activity))) }
        tickNeeds(dt)
        let ta = platform.now()
        syncAttachment(dt)
        Perf.add("sync", platform.now() - ta)

        if action == nil { advance() }
        if let a = action {
            a.t += dt
            if !a.step(self, dt) {
                a.end(self)
                if action === a { action = nil }
                advance()
            }
        }
        if let a = action, a.grounded, case .window = surface {
            if hostShake > 2100 { interrupt(with: [Slip(cause: .shaken)]) }
            else if hostShake > 650 { wobble = 0.45 }
        }

        applyOverlays(dt)
        // Grumpiness shows on the face (except while asleep or eating).
        if grumpy > 0.3, action?.showsMood ?? true { target = target.grumpy(min(1, (grumpy - 0.3) / 0.35)) }
        pose.blend(toward: target, 1 - exp(-blendRate * dt))
        updateTurn(dt)
        displayPose = pose
        decorate(&displayPose, dt)
        effects.update(dt)
        placeWindow()
        updateMouse()
        if Cat.debug, Int(time * 60) % 10 == 0 {
            try? "\(Int(pos.x)) \(Int(pos.y)) \(String(describing: type(of: action ?? Act())))".write(toFile: "/tmp/mochi-pos-\(name).txt", atomically: true, encoding: .utf8)
        }
        // Fully hidden behind other windows: nothing to draw.
        if sprite.isVisible || dragging { sprite.setNeedsDisplay() }
    }

    private func advance() {
        while action == nil {
            if queue.isEmpty {
                world.refreshIfStale()
                decide()
            }
            guard !queue.isEmpty else { return }
            let next = queue.removeFirst()
            action = next
            next.begin(self)
            if Cat.debug {
                print(String(format: "%7.2f %@ %@  pos=(%.0f,%.0f) surface=%@ depth=%@", time, name,
                             String(describing: type(of: next)), pos.x, pos.y,
                             String(describing: surface), String(describing: depth)))
            }
        }
    }

    /// Drop whatever it's doing and start something new.
    func interrupt(with acts: [Act]) {
        if let a = action { a.end(self) }
        action = nil
        queue = acts
        advance()
    }

    enum Request { case home, nap }
    var request: Request?

    /// Ask for something from the menu. Takes effect now if the cat is on its feet,
    /// otherwise as soon as it lands.
    func ask(_ r: Request) {
        request = r
        if action == nil || action!.grounded || surface == .box {
            action?.end(self)
            action = nil
            queue = []
        }
    }

    // MARK: - Turning around

    private func updateTurn(_ dt: CGFloat) {
        if turnT == nil && (target.view != shownView || facing != shownFacing) { turnT = 0 }
        guard var t = turnT else { return }
        let before = t
        t += dt / 0.17
        if before < 0.5 && t >= 0.5 {
            // Swap at the narrowest point so the change is hidden.
            if target.view != shownView { pose = target }
            shownView = target.view
            shownFacing = facing
        }
        turnT = t >= 1 ? nil : t
    }

    /// Change view/direction instantly (e.g. a sudden slip).
    func snapTurn() {
        shownView = target.view
        shownFacing = facing
        pose = target
        turnT = nil
    }

    var renderScaleX: CGFloat {
        guard let t = turnT else { return shownFacing }
        return shownFacing * (1 - 0.8 * sin(.pi * t))
    }

    // MARK: - Life overlays (blinks, glances, ear flicks)

    private func applyOverlays(_ dt: CGFloat) {
        if lookAtCursor {
            let head = headWorld
            let m = Coords.mouse
            let dx = m.x - head.x, dy = head.y - m.y
            let d = hypot(dx, dy)
            if d < 320 {
                target.lookX = max(-1, min(1, dx / 90)) * (shownView == .side ? shownFacing : 1)
                target.lookY = max(-1, min(1, dy / 90))
            } else {
                target.lookX = sin(time * 0.37) * 0.5 * (shownView == .side ? 1 : 0.6)
                target.lookY = sin(time * 0.23) * 0.3
            }
        }
    }

    private func decorate(_ p: inout Pose, _ dt: CGFloat) {
        if allowBlink && p.eyes == .open {
            blinkClock -= dt
            if blinkClock <= 0 {
                blinkT = 0
                blinkClock = .random(in: 2.2...6.5)
                if Int.random(in: 0..<5) == 0 { blinkClock = 0.32 } // double blink
            }
        }
        if blinkT >= 0 {
            blinkT += dt
            let k = blinkT / 0.15
            if k >= 1 { blinkT = -1 } else { p.eyeOpen *= 1 - sin(.pi * k) * 0.95 }
        }
        twitchClock -= dt
        if twitchClock <= 0 { twitchT = 0; twitchClock = .random(in: 3...9) }
        if twitchT >= 0 {
            twitchT += dt
            if twitchT > 0.22 { twitchT = -1 } else { p.earTwitch += sin(.pi * twitchT / 0.22) * 0.7 }
        }
        if wobble > 0 {
            wobble -= dt
            p.rotation += sin(time * 30) * 0.08 * min(1, wobble * 3)
            if p.view == .side { p.eyes = .wide; p.earPerk = 0.4 }
        }
    }

    // MARK: - Geometry helpers

    /// Head position in cat-local (unmirrored) coordinates, for effects.
    var headLocal: CGPoint {
        shownView == .side ? CGPoint(x: pose.head.x * shownFacing, y: pose.head.y) : pose.fHead
    }

    var headWorld: CGPoint {
        let h = headLocal
        return CGPoint(x: pos.x + h.x * scale, y: pos.y - h.y * scale)
    }

    /// Does the cat's body cover this global point?
    func contains(_ m: CGPoint) -> Bool {
        if case .hidden? = overlay { return false }
        let lx = (m.x - pos.x) / scale * (shownView == .side ? shownFacing : 1)
        let ly = (pos.y - m.y) / scale
        let p = CGPoint(x: lx, y: ly)
        let rects: [CGRect]
        if shownView == .side {
            let b = pose.body, h = pose.head
            rects = [CGRect(x: b.x - pose.bodyW / 2 - 3, y: min(0, b.y - pose.bodyH / 2) - 2, width: pose.bodyW + 6, height: pose.bodyH + b.y + 4),
                     CGRect(x: h.x - 19, y: h.y - 17, width: 38, height: 44)]
        } else {
            let b = pose.fBody, h = pose.fHead
            rects = [CGRect(x: b.x - pose.fBodyW / 2 - 3, y: b.y - pose.fBodyH / 2 - 8, width: pose.fBodyW + 6, height: pose.fBodyH + 10),
                     CGRect(x: h.x - 19, y: h.y - 17, width: 38, height: 44)]
        }
        return rects.contains { $0.contains(p) }
    }

    func spawn(_ kind: FXKind, dx: CGFloat = 0, dy: CGFloat = 0, v: CGPoint = CGPoint(x: 0, y: 30), life: CGFloat = 1.5) {
        let h = headLocal
        effects.spawn(kind, at: CGPoint(x: h.x + dx, y: h.y + dy), v: v, life: life)
    }

    // MARK: - Standing, attachment, depth

    func stand(on s: Surface, x: CGFloat) {
        surface = s.ref
        pos = CGPoint(x: x, y: s.y)
        switch s.ref {
        case .floor: attach = nil
        default: attach = s.ref
        }
    }

    /// Where in the window stack a cat ends up after landing on `s`.
    func depthAfterLanding(on s: Surface) -> Depth {
        switch s.ref {
        case .window(let id): return .above(id)
        case .box: return .inBox
        case .bowls: return .atBowls
        case .floor:
            switch depth {
            case .top, .onBox, .inBox, .atBowls:
                // Put down in front of whatever window is here, so it stays visible.
                if let w = world.frontmost(at: CGPoint(x: pos.x, y: s.y - 10)) { return .above(w.id) }
                return .desktop
            case .above(let id) where world.window(id) == nil:
                return .desktop
            default:
                return depth
            }
        }
    }

    private func syncAttachment(_ dt: CGFloat) {
        guard let a = attach else { return }
        let frame: CGRect?
        switch a {
        case .window(let id):
            // Poll the window every frame only while it's moving (being dragged or wobbling).
            syncCounter += 1
            if time - hostMovedAt < 1.2 || syncCounter % 6 == 0 || attachFrame == nil {
                frame = world.liveFrame(id)
            } else {
                frame = attachFrame
            }
        case .box: frame = home.frameCG
        case .bowls: frame = Den.shared.bowls?.frameCG
        case .floor: frame = nil
        }
        guard let f = frame else {
            attach = nil
            if case .window = surface { surface = nil }
            action?.supportLost(self)
            return
        }
        if let old = attachFrame {
            let dy = f.minY - old.minY
            let dx = abs(f.width - old.width) < 0.5 ? f.minX - old.minX : 0
            if dx != 0 || dy != 0 {
                hostMovedAt = time
                pos.x += dx
                pos.y += dy
                hostShake = max(hostShake, hypot(dx, dy) / max(dt, 1 / 120))
            }
            if f.width != old.width, let s = currentSurface, pos.x < s.minX - 8 || pos.x > s.maxX + 8 {
                // The window was resized out from under its paws.
                action?.supportLost(self)
            }
        }
        attachFrame = f
    }

    func applyDepth() {
        let level: SpriteLevel
        switch depth {
        case .desktop: level = .desktop
        case .above: level = .normal
        case .top: level = .carried
        case .inBox, .onBox: level = home.level
        case .atBowls: level = Den.shared.bowls?.level ?? .floating
        }
        if sprite.level != level { sprite.level = level }
        switch depth {
        case .desktop, .top: sprite.orderFront()
        case .above(let id): sprite.order(above: id)
        case .inBox:
            // Tuck in just behind the front wall. (Moving the wall up to the cat instead would leave
            // any cat already in the box standing in front of it.)
            sprite.order(below: home.front.id)
        case .onBox: sprite.order(above: home.front.id)
        case .atBowls:
            if let b = Den.shared.bowls { sprite.order(below: b.sprite.id) }
        }
        appliedDepth = depth
    }

    /// After the window list refreshes: make sure nothing has slipped between the cat and its window.
    func verifyStack() {
        guard !paused else { return }
        reanchor()
        let me = sprite.id
        let stack = world.stack
        switch depth {
        case .above(let id):
            guard world.window(id) != nil else {
                if surface?.windowID == nil, let floor = world.surface(.floor(screenIndex)) {
                    depth = depthAfterLanding(on: floor)
                }
                return
            }
            guard let mi = stack.firstIndex(of: me), let hi = stack.firstIndex(of: id) else { applyDepth(); return }
            let between = mi < hi ? stack[(mi + 1)..<hi] : []
            let foreign = between.contains { w in !world.isOwn(w) }
            if mi > hi || foreign { applyDepth() }
        case .inBox:
            let b = home.back.id, f = home.front.id
            if let mi = stack.firstIndex(of: me), let bi = stack.firstIndex(of: b), let fi = stack.firstIndex(of: f),
               !(fi < mi && mi < bi) { applyDepth() }
        default:
            if appliedDepth != depth { applyDepth() }
        }
    }

    /// A cat that isn't standing on its anchor window keeps its place among the windows *around it*.
    /// Without this, activating the anchor window on another screen would drag the cat in front of everything.
    private func reanchor() {
        guard case .above(let anchor) = depth else { return }
        if surface == .window(anchor) || attach == .window(anchor) { return }
        let area = CGRect(x: pos.x - 70 * scale, y: pos.y - 90 * scale, width: 140 * scale, height: 100 * scale)
        let prev = world.prevZ
        if let a = world.window(anchor) {
            let sameScreen = world.screenIndex(at: CGPoint(x: a.frame.midX, y: a.frame.minY)) == screenIndex
            let shuffled = prev[anchor].map { $0 != a.z } ?? false
            if sameScreen && (!shuffled || a.frame.intersects(area)) { return }
        }
        guard let za = prev[anchor] ?? world.window(anchor)?.z else { return }
        let zc = Double(za) + 0.5
        // Frontmost nearby window that was behind the cat a moment ago.
        let best = world.windows
            .filter { $0.frame.intersects(area) }
            .compactMap { w -> (WinInfo, Int)? in
                guard let pz = prev[w.id] ?? (w.id == anchor ? za : nil), Double(pz) < zc else { return nil }
                return (w, pz)
            }
            .max { $0.1 < $1.1 }
        let next: Depth = best.map { .above($0.0.id) } ?? .desktop
        if next != depth { depth = next }
    }

    private func placeWindow() {
        let o = CGPoint(x: ((pos.x - anchor.x) * 2).rounded() / 2,
                        y: ((pos.y + anchor.y) * 2).rounded() / 2 - sprite.size.height)
        if sprite.origin != o {
            let t0 = platform.now()
            sprite.origin = o
            Perf.add("move", platform.now() - t0)
        }
    }

    func show() {
        sprite.orderFront()
        applyDepth()
    }

    /// After a romp in front of everything, slot back into the window stack where nobody will notice.
    func settleDepth() {
        guard depth == .top, let s = currentSurface else { return }
        depth = depthAfterLanding(on: s)
    }

    // MARK: - Drawing

    /// Cat-local box that holds everything drawn this frame (effects that drift further get clipped).
    private var localBox: CGRect {
        let hangs = shownView == .front && pose.fBody.y < 5
        return hangs ? CGRect(x: -72, y: -112, width: 144, height: 240) : CGRect(x: -72, y: -14, width: 144, height: 142)
    }

    /// Only the box around the cat is drawn and uploaded, not the whole (mostly empty) window.
    var drawingBounds: CGRect? {
        if case .hidden? = overlay { return .zero }
        let b = localBox
        return CGRect(x: anchor.x + b.minX * scale, y: anchor.y + b.minY * scale,
                      width: b.width * scale, height: b.height * scale)
    }

    func draw(_ ctx: CGContext) {
        if case .hidden? = overlay { return }
        let t0 = platform.now()
        defer { Perf.add("draw", platform.now() - t0) }
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.saveGState()
        if depth == .inBox {
            // Toes and tail stay inside the box instead of poking out under it.
            let bottom = HomeBox.frontRect.minY - HomeBox.rimLocal.y
            ctx.clip(to: CGRect(x: -200, y: bottom, width: 400, height: 400))
        }
        ctx.scaleBy(x: renderScaleX, y: 1)
        if case .fight(let other)? = overlay {
            CatRenderer(coat: coat, time: time).drawFightCloud(ctx, other: other)
        } else {
            var p = displayPose
            p.view = shownView
            CatRenderer(coat: coat, time: time).draw(ctx, pose: p)
        }
        ctx.restoreGState()
        effects.draw(ctx)
        ctx.restoreGState()
    }

    // MARK: - Mouse

    private func updateMouse() {
        let want = dragging || press != nil || contains(Coords.mouse)
        if sprite.clickThrough == want { sprite.clickThrough = !want }
    }

    func mouseDown() { press = Coords.mouse }

    func rightMouseDown() { onContextMenu?() }

    func mouseDragged() {
        guard let p = press, !dragging else { return }
        let m = Coords.mouse
        if hypot(m.x - p.x, m.y - p.y) > 4 {
            dragging = true
            interrupt(with: [Held()])
        }
    }

    func mouseUp() {
        if dragging {
            dragging = false
            (action as? Held)?.release(self)
        } else if press != nil {
            pet()
        }
        press = nil
    }

    func pet() {
        if grumpy > 0.25, let a = action, a.grounded || surface == .box, !(a is Sleep) {
            if grumpy > 0.55 && isStarving {
                // Not until there's food in that bowl.
                interrupt(with: [Swat(), Sulk(.random(in: 4...7))])
            } else {
                grumpy = max(0, grumpy - 0.18)
                effects.say("hmph", at: CGPoint(x: headLocal.x, y: headLocal.y + 18), color: .systemBrown)
                if grumpy < 0.3 { effects.hearts(at: CGPoint(x: headLocal.x, y: headLocal.y + 14), count: 1) }
            }
            return
        }
        if let a = action, a.onPet(self) { return }
        effects.hearts(at: CGPoint(x: headLocal.x, y: headLocal.y + 14), count: 1)
    }
}

