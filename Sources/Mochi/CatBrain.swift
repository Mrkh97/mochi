import Foundation

func chance(_ p: CGFloat) -> Bool { CGFloat.random(in: 0...1) < p }

func pick<T>(_ options: [(T, CGFloat)]) -> T? {
    let total = options.reduce(0) { $0 + max(0, $1.1) }
    guard total > 0 else { return nil }
    var r = CGFloat.random(in: 0..<total)
    for (o, w) in options where w > 0 {
        if r < w { return o }
        r -= w
    }
    return options.last?.0
}

extension Cat {
    var activityBoost: CGFloat { min(1.3, max(0.85, activity)) }

    /// Pick the next activity when the queue runs dry.
    func decide() {
        guard let s = currentSurface else { queue = [Fall()]; return }
        if let r = request {
            request = nil
            switch r {
            case .home: goHome(thenSleep: false)
            case .nap: energy = min(energy, 0.1); planNap()
            }
            if !queue.isEmpty { return }
        }
        if s.ref == .box { decideInBox(); return }

        // Food and water come first.
        if isHungry || isThirsty {
            let drink = (thirst - 0.5) > (hunger - 0.55)
            let empty = bowls.amount(drink: drink) < 0.03
            if !empty || time - lastComplain > 30 {
                if empty { lastComplain = time }
                if goToBowls(drink: drink) { return }
            }
        }
        if s.ref == .bowls {
            // Done here: hop down off the mat.
            let dir: CGFloat = Bool.random() ? 1 : -1
            queue = [Walk(to: dir < 0 ? s.minX : s.maxX, speed: 55), HopOff(dir: dir)]
            return
        }
        if grumpy > 0.5 { planGrump(); return }

        if energy < 0.22 || (energy < 0.45 && chance(0.12)) { planNap(); return }

        // Hang out with the other cats now and then.
        if Den.shared.cats.count > 1, chance((Cat.testMode ? 0.5 : 0.22) * activity), planSocial() { return }

        enum Choice { case wander, idle, groom, stretch, explore, zoomies, home, hide, peekOut, travel }
        let hidden = isHidden
        hiddenSince = hidden ? (hiddenSince ?? time) : nil
        if let h = hiddenSince, time - h > 40 {
            // Been stuck behind windows for a while (say, a maximised app): head home.
            hiddenSince = nil
            goHome(thenSleep: false)
            return
        }
        let onWindow: Bool = { if case .window = s.ref { return true } else { return false } }()
        // Another display to visit; more tempting if that's where you are.
        let away = travelTarget
        let followYou = away.map { $0 == world.screenIndex(at: Coords.mouse) } ?? false
        let choice = pick([
            (Choice.wander, 2.6),
            (.idle, 2.2),
            (.groom, 1.0),
            (.stretch, 0.4),
            (.explore, (hidden ? 4.5 : 3.0 * activity) * (Cat.testMode ? 4 : 1)),
            (.zoomies, energy > 0.6 && s.width > 400 ? 0.22 * activity : 0),
            (.home, 0.2),
            (.hide, onWindow ? 0.35 : 0),
            (.peekOut, hidden ? 2.5 : 0),
            (.travel, away == nil ? 0 : (followYou ? 1.3 : 0.3) * activity * (Cat.travelTest ? 40 : 1)),
        ]) ?? .idle

        switch choice {
        case .wander:
            let x = s.clamp(pos.x + .random(in: -320...320))
            queue = [Walk(to: x, speed: .random(in: 42...68))]
        case .idle:
            let style = pick([(Idle.Style.sit, 3.0), (.loaf, 1.5), (.sitFront, 1.2), (.stand, 0.4)]) ?? .sit
            queue = [Idle(style, .random(in: 3...9))]
        case .groom:
            queue = [Idle(.sit, 0.6), Groom(.random(in: 3.5...7))]
        case .stretch:
            queue = [Stretch()]
        case .explore:
            if !planMove(from: s) { queue = [Walk(to: s.clamp(pos.x + .random(in: -200...200)))] }
        case .zoomies:
            var acts: [Act] = []
            var x = pos.x
            for i in 0..<Int.random(in: 3...5) {
                x = i % 2 == 0 ? s.minX + .random(in: 10...80) : s.maxX - .random(in: 10...80)
                if Bool.random() && i == 0 { x = s.clamp(pos.x + (pos.x < (s.minX + s.maxX) / 2 ? 400 : -400)) }
                acts.append(Walk(to: x, speed: .random(in: 300...380), zoom: true))
            }
            acts.append(contentsOf: [Idle(.sit, 0.8), Groom(3)])
            queue = acts
        case .home:
            goHome(thenSleep: false)
        case .hide:
            queue = [Walk(to: s.clamp(pos.x + .random(in: -120...120))), HopOff(dir: facing, behind: true)]
        case .peekOut:
            planPeekOut(s)
        case .travel:
            if let j = away, travel(to: j) { break }
            queue = [Idle(.sit, 2)]
        }
    }

    private func decideInBox() {
        if isHungry || isThirsty {
            let drink = (thirst - 0.5) > (hunger - 0.55)
            if bowls.amount(drink: drink) > 0.03 || time - lastComplain > 30, goToBowls(drink: drink) {
                if bowls.amount(drink: drink) < 0.03 { lastComplain = time }
                return
            }
        }
        if grumpy > 0.5 && chance(0.5) { queue = [BoxIdle(.random(in: 3...6))]; return }
        if energy < 0.3 { queue = [Sleep(.random(in: 30...80) / activity)]; return }
        if chance(0.3) { queue = [BoxIdle(.random(in: 4...9))]; return }
        guard let floor = world.surface(.floor(screenIndex)) else { queue = [BoxIdle(4)]; return }
        // Hop out: onto a nearby window top, or down to the floor.
        var options: [((SurfaceRef, CGFloat), CGFloat)] = []
        for t in world.windowSurfaces(screen: screenIndex) {
            let lx = t.clamp(pos.x + .random(in: -160...160))
            let dx = abs(lx - pos.x), rise = pos.y - t.y
            if dx < 520 && rise < 380 && !world.covered(CGPoint(x: lx, y: t.y - 4), above: t.z) {
                options.append(((t.ref, lx), 1.4))
            }
        }
        let fx = floor.clamp(pos.x + (Bool.random() ? 1 : -1) * .random(in: 90...240))
        options.append(((floor.ref, fx), 1.6))
        guard let (dest, lx) = pick(options) else { queue = [BoxIdle(4)]; return }
        let dir: CGFloat = lx >= pos.x ? 1 : -1
        queue = [LeaveBox(dir: dir), Jump(to: dest, x: lx, crouch: 0.4, canSlip: false)]
    }

    /// Is the cat currently behind some window?
    var isHidden: Bool {
        world.covered(CGPoint(x: pos.x, y: pos.y - 20 * scale), above: z)
    }

    // MARK: Naps

    func planNap() {
        guard let s = currentSurface else { return }
        let d = CGFloat.random(in: 60...170) / max(0.6, activity)
        // Snuggle up next to a friend who's already asleep.
        if let f = Den.shared.others(than: self).first(where: { $0.isAsleep && $0.surface == s.ref && $0.surface != .box }),
           chance(0.8) {
            let side: CGFloat = pos.x < f.pos.x ? -1 : 1
            queue = [Walk(to: s.clamp(f.pos.x + side * 44 * scale), speed: 50), Sleep(d)]
            return
        }
        if case .window = s.ref, chance(0.7) {
            queue = [Walk(to: s.clamp(pos.x + .random(in: -150...150))), Sleep(d)]
        } else if chance(0.55) {
            goHome(thenSleep: true)
        } else {
            queue = [Sleep(d)]
        }
    }

    // MARK: Going home

    func goHome(thenSleep: Bool) {
        let box = home.surface
        let after: [Act] = thenSleep ? [Sleep(.random(in: 40...90) / max(0.6, activity))] : []
        if surface == .box { queue = after.isEmpty ? [BoxIdle(6)] : after; return }
        guard let s = currentSurface else { return }
        // The box is on another display: get over there first.
        if let hs = world.screenIndex(of: .box), hs != screenIndex, travel(to: hs, then: [GoHomeLater(sleep: thenSleep)]) { return }
        let dx = abs(box.minX - pos.x), rise = s.y - box.y
        let zBox = box.z
        let canReach = (dx < 700 && rise < 600) || { if case .floor = s.ref { return true } else { return false } }()
        // Take off from a spot that isn't hidden behind a window, so the cat doesn't pop through it.
        func clear(_ x: CGFloat) -> Bool { zBox <= z || !world.covered(CGPoint(x: x, y: s.y - 20), above: z, upTo: zBox) }
        let side: CGFloat = pos.x < box.minX ? -1 : 1
        var launch = s.clamp(box.minX + side * .random(in: 60...140))
        if !clear(launch), let x = stride(from: 40, through: 900, by: 40).lazy
            .flatMap({ d in [box.minX - CGFloat(d), box.maxX + CGFloat(d)] })
            .first(where: { $0 > s.minX && $0 < s.maxX && clear($0) }) {
            launch = x
        }
        if canReach {
            let lx = launch
            queue = [Walk(to: lx, speed: 70), Jump(to: .box, x: (box.minX + box.maxX) / 2, crouch: 0.6, canSlip: false)] + after
        } else if case .window = s.ref {
            // Get down first, then head home.
            let dir: CGFloat = box.minX < pos.x ? -1 : 1
            queue = [Walk(to: dir < 0 ? s.minX : s.maxX, speed: 70), HopOff(dir: dir), GoHomeLater(sleep: thenSleep)]
        } else {
            queue = [Idle(.sit, 2)]
        }
    }

    // MARK: Exploring the window landscape

    /// Choose one hop to another surface (jump, climb behind, or drop down). Returns false if stuck.
    @discardableResult
    func planMove(from s: Surface) -> Bool {
        enum Move { case jump(Surface, CGFloat, CGFloat), climb(Surface, CGFloat, (CGFloat, Depth)?), hop(CGFloat), behind }
        var moves: [(Move, CGFloat)] = []
        let zc = z
        let si = screenIndex
        let sid: CGWindowID? = { if case .window(let id) = s.ref { return id } else { return nil } }()

        for t in world.windowSurfaces(screen: si) {
            if case .window(let id) = t.ref, id == sid { continue }
            let dir: CGFloat = t.minX + t.maxX > 2 * pos.x ? 1 : -1
            // Landing spot: somewhere on t near the cat.
            let lx = t.clamp(pos.x + dir * .random(in: 40...260))
            let launchX = s.clamp(lx - dir * .random(in: 30...150))
            let dx = abs(lx - launchX), rise = s.y - t.y
            let launchPt = CGPoint(x: launchX, y: s.y - 20)
            let landPt = CGPoint(x: lx, y: t.y - 4)
            let landVisible = !world.covered(landPt, above: t.z)

            // Climbing up the back of a window and peeking over the top.
            if rise > 70 {
                let lo = max(s.minX, t.minX + 10), hi = min(s.maxX, t.maxX - 10)
                if hi > lo {
                    let cx = min(hi, max(lo, pos.x + .random(in: -200...200)))
                    let snug = t.y + 30 < s.y && (world.window(t.ref.windowID!)?.frame.maxY ?? 0) > s.y - 140
                    let w = (snug ? 2.2 : 0.5) * (landVisible ? 1 : 0.4)
                    if t.z > zc {
                        moves.append((.climb(t, cx, nil), w))
                    } else if case .floor = s.ref, let sneak = sneakSpot(on: s, behind: t.ref.windowID!) {
                        // In front of it: slip round the back where nobody can see, then climb.
                        moves.append((.climb(t, cx, sneak), w * 0.9))
                    }
                }
            }
            guard rise < 440, dx < 480, rise > -720 else { continue }
            if t.z > zc && world.covered(launchPt, above: zc, upTo: t.z) { continue }
            if t.z <= zc && world.covered(landPt, above: t.z, upTo: zc) { continue }
            if rise > 0 && dx < 26 && t.z > zc { continue }
            var w: CGFloat = landVisible ? 1.6 : 0.25
            w *= 1 + min(1, t.width / 1400)
            w *= rise > 0 ? 1.2 : 0.8
            moves.append((.jump(t, launchX, lx), w))
        }
        if sid != nil {
            for dir: CGFloat in [-1, 1] {
                let ex = dir < 0 ? s.minX : s.maxX
                if let l = world.landing(x: ex + dir * 34, fromY: s.y, z: zc, screen: si), l.ref != s.ref {
                    moves.append((.hop(dir), l.ref == .floor(si) ? 0.7 : 1.1))
                }
            }
            moves.append((.behind, 0.35))
        }
        // Prefer destinations that don't need a marathon walk first.
        func walk(_ m: Move) -> CGFloat {
            switch m {
            case .jump(_, let x, _): return abs(x - pos.x)
            case .climb(_, let x, let sneak): return abs((sneak?.0 ?? x) - pos.x) + abs(x - (sneak?.0 ?? x))
            case .hop(let d): return abs((d < 0 ? s.minX : s.maxX) - pos.x)
            case .behind: return 0
            }
        }
        moves = moves.map { ($0.0, $0.1 / (1 + walk($0.0) / 350)) }
        guard let m = pick(moves) else { return false }
        switch m {
        case .jump(let t, let launchX, let lx):
            queue = [Walk(to: launchX, speed: .random(in: 50...75)), Jump(to: t.ref, x: lx)]
        case .climb(let t, let cx, let sneak):
            if let (sx, d) = sneak {
                queue = [Walk(to: sx, speed: .random(in: 50...70)), SetDepth(d),
                         Walk(to: cx, speed: .random(in: 50...70)), Climb(t.ref.windowID!)]
            } else {
                queue = [Walk(to: cx, speed: .random(in: 50...70)), Climb(t.ref.windowID!)]
            }
        case .hop(let dir):
            queue = [Walk(to: dir < 0 ? s.minX : s.maxX, speed: .random(in: 45...65)), HopOff(dir: dir)]
        case .behind:
            queue = [HopOff(dir: facing, behind: true)]
        }
        return true
    }

    /// The depth just behind window `id`.
    func depthBehind(_ id: CGWindowID) -> Depth {
        let ws = world.windows
        guard let i = ws.firstIndex(where: { $0.id == id }), i + 1 < ws.count else { return .desktop }
        return .above(ws[i + 1].id)
    }

    /// A spot on `s` where the cat can step behind window `id` without visibly popping through anything.
    func sneakSpot(on s: Surface, behind id: CGWindowID) -> (CGFloat, Depth)? {
        let d = depthBehind(id)
        let zNew = world.z(of: d), zc = z
        func clear(_ x: CGFloat) -> Bool {
            let probes = [CGPoint(x: x, y: s.y - 15), CGPoint(x: x - 28 * scale, y: s.y - 15),
                          CGPoint(x: x + 28 * scale, y: s.y - 15), CGPoint(x: x, y: s.y - 50 * scale)]
            return !probes.contains { world.covered($0, above: zNew, upTo: zc) }
        }
        for step in 0..<40 {
            for sign: CGFloat in [1, -1] {
                let x = pos.x + sign * CGFloat(step) * 30
                if x > s.minX + 20 && x < s.maxX - 20 && clear(x) { return (x, d) }
            }
        }
        return nil
    }

    /// Hidden behind a window: walk until just the head pokes out past its edge.
    private func planPeekOut(_ s: Surface) {
        guard let w = world.windows.first(where: { Double($0.z) > z && $0.frame.contains(CGPoint(x: pos.x, y: pos.y - 20)) }) else {
            queue = [Idle(.sit, 2)]; return
        }
        let left = abs(pos.x - w.frame.minX) < abs(w.frame.maxX - pos.x)
        let edge = left ? w.frame.minX : w.frame.maxX
        let x = edge + (left ? 12 : -12) * scale
        guard x > s.minX && x < s.maxX else { planMove(from: s); return }
        queue = [Walk(to: x, speed: 55), Idle(.stand, .random(in: 1.8...3.5))]
        if chance(0.6) { queue.append(Walk(to: s.clamp(edge + (left ? -90 : 90) * scale))) }
    }

    // MARK: Playing with the pointer

    /// Pounce at the pointer when it skitters along the cat's ledge.
    func considerPlay(_ mouseSpeed: CGFloat) {
        guard time - lastPlay > 12, energy > 0.35, mouseSpeed > 260,
              let a = action, a is Idle || a is Walk, let s = currentSurface, s.ref != .box else { return }
        let m = Coords.mouse
        guard abs(m.y - (s.y - 12)) < 45, abs(m.x - pos.x) < 260, abs(m.x - pos.x) > 40,
              m.x > s.minX, m.x < s.maxX, chance(0.5 * activity) else { return }
        lastPlay = time
        interrupt(with: [Jump(to: s.ref, x: m.x, crouch: .random(in: 0.5...0.9), canSlip: chance(0.3)),
                         Idle(.sit, 1.2)])
        spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
    }
}

/// Quietly change place in the window stack (only used where nothing covers the cat).
final class SetDepth: Act {
    let depth: Depth
    init(_ d: Depth) { depth = d }
    override func begin(_ c: Cat) { c.depth = depth }
}

/// Re-plans the trip home once the cat has climbed down.
final class GoHomeLater: Act {
    let sleep: Bool
    init(sleep: Bool) { self.sleep = sleep }
    override func begin(_ c: Cat) { c.goHome(thenSleep: sleep) }
}

extension SurfaceRef {
    var windowID: CGWindowID? { if case .window(let id) = self { return id } else { return nil } }
}
