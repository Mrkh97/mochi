import AppKit

extension Cat {
    /// Where the front paws are while leaping (for catching things), CG coords.
    var pawWorld: CGPoint { CGPoint(x: pos.x + facing * 30 * scale, y: pos.y - 17 * scale) }

    /// Holding the yarn ball (playing with it, or falling/landing with it right after a catch).
    var carryingToy: Bool {
        action is PlayWithToy || ((action is Fall || action is Land) && queue.contains { $0 is PlayWithToy })
    }

    /// Walk (or run) toward x on the current ledge. Returns true on arrival.
    @discardableResult
    func trot(to x: CGFloat, speed: CGFloat, _ dt: CGFloat) -> Bool {
        let dx = x - pos.x
        if abs(dx) < 2 { target = .stand(); return true }
        facing = dx > 0 ? 1 : -1
        let move = min(abs(dx), speed * scale * dt)
        pos.x += facing * move
        walkPhase += move / (8 * scale)
        target = .walk(phase: walkPhase, speed: move / max(dt, 0.001) / scale)
        return false
    }

    /// Point the eyes at something.
    func look(at p: CGPoint) {
        let h = headWorld
        target.lookX = max(-1, min(1, (p.x - h.x) / 80)) * (shownView == .side ? facing : 1)
        target.lookY = max(-1, min(1, (h.y - p.y) / 80))
    }

    /// A moving yarn ball nearby is irresistible.
    func considerToy(_ dt: CGFloat) {
        guard let toy = Den.shared.toy, toy.visible, toy.state != .caught, overlay == nil,
              time - lastToyChase > 5, grumpy < 0.5, energy > 0.15,
              let a = action, a is Idle || a is Walk || a is Groom || a is Stretch || a is BoxIdle,
              let s = currentSurface, world.screenIndex(at: toy.p) == screenIndex else { return }
        let d = hypot(toy.p.x - pos.x, toy.p.y - pos.y)
        guard d < 700 * scale else { return }
        let lively = toy.speed > 70
        let perSecond: CGFloat = lively ? 2.2 * activity : (d < 260 * scale ? 0.05 : 0)
        guard chance(perSecond * dt * (Cat.testMode ? 3 : 1)) else { return }
        lastToyChase = time
        if s.ref == .box {
            // Spring out of the box after it.
            guard let floor = world.surface(.floor(screenIndex)) else { return }
            let dir: CGFloat = toy.p.x > pos.x ? 1 : -1
            interrupt(with: [LeaveBox(dir: dir), Jump(to: floor.ref, x: floor.clamp(pos.x + dir * 110 * scale), crouch: 0.2, canSlip: false),
                             ChaseToy()])
        } else {
            interrupt(with: [ChaseToy()])
        }
        spawn(.exclaim, dx: 12, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.6)
    }
}

/// Stalk the yarn ball: run under it, hop down to it, jump across to it, pounce when in range.
final class ChaseToy: Act {
    var budget: CGFloat
    private var watching: CGFloat = 0

    init(_ budget: CGFloat = .random(in: 14...24)) { self.budget = budget }
    override var status: String { "Chasing the yarn ball!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 14
        c.lookAtCursor = false
        // Play happens in front of everything, but only switch where it can't be seen popping.
        if !c.isHidden { c.depth = .top }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        budget -= dt
        let toy = Den.shared.toy!
        guard budget > 0, toy.visible, let s = c.currentSurface else { c.settleDepth(); return false }
        if toy.state == .caught {
            // Another cat has it: maybe tackle them for it.
            if let h = toy.holder, h !== c, h.surface == c.surface, abs(h.pos.x - c.pos.x) < 300 * c.scale, chance(0.5) {
                h.interrupt(with: [BeWrestled(c)])
                c.queue.insert(PounceFriend(h), at: 0)
            } else {
                c.settleDepth()
            }
            return false
        }
        let tp = toy.p
        let dx = tp.x - c.pos.x
        let above = s.y - (tp.y + toy.r)          // ball height over this ledge (negative = below it)
        let onLedge = tp.x > s.minX - 30 && tp.x < s.maxX + 30
        let onFloor: Bool = { if case .floor = s.ref { return true } else { return false } }()

        if onLedge && above > -25 && above < 210 * c.scale && abs(dx) < 240 * c.scale {
            if abs(dx) > 4 { c.facing = dx > 0 ? 1 : -1 }
            c.queue.insert(contentsOf: [Pounce(), ChaseToy(budget)], at: 0)
            return false
        }
        if onLedge && above > -25 && above < 650 {
            // Run toward it (or under it), staring.
            let goal = s.clamp(tp.x - (dx > 0 ? 1 : -1) * 90 * c.scale)
            if c.trot(to: goal, speed: 250, dt) {
                if abs(dx) > 4 { c.facing = dx > 0 ? 1 : -1 }
                c.target = .crouch(wiggle: 0)
            } else {
                c.target.earPerk = 0.6
                c.target.eyeOpen = 1.12
            }
            c.look(at: tp)
            watching = 0
            return true
        }
        if above < -25 && !onFloor {
            // It's down below: hop off this ledge toward it.
            let dir: CGFloat = dx > 0 ? 1 : -1
            c.queue.insert(contentsOf: [Walk(to: dir < 0 ? s.minX : s.maxX, speed: 220), HopOff(dir: dir), ChaseToy(budget)], at: 0)
            return false
        }
        if toy.state != .flying, toy.state != .held, let ref = toy.surface, ref != s.ref, let ts = c.world.surface(ref) {
            let lx = ts.clamp(tp.x - (dx > 0 ? 1 : -1) * 60 * c.scale)
            if s.y - ts.y < 440 && abs(lx - c.pos.x) < 520 {
                c.queue.insert(contentsOf: [Jump(to: ref, x: lx, crouch: 0.3, canSlip: false), ChaseToy(budget)], at: 0)
                return false
            }
        }
        // Out of reach: just watch it, very intently.
        watching += dt
        if abs(dx) > 4 { c.facing = dx > 0 ? 1 : -1 }
        c.target = .crouch(wiggle: 0)
        c.look(at: tp)
        if watching > 4 { c.settleDepth(); return false }
        return true
    }
}

/// Wiggle, then leap at the ball (aiming a little ahead of where it's going). Can catch it mid-air.
final class Pounce: Act {
    private var launched = false
    private var p0 = CGPoint.zero
    private var p1 = CGPoint.zero
    private var vy0: CGFloat = 0
    private var T: CGFloat = 0.4
    private var tLaunch: CGFloat = 0
    private let crouch = CGFloat.random(in: 0.3...0.7)
    private let g: CGFloat = 2600
    private var touched = false

    override var status: String { "Pounce!" }
    override var grounded: Bool { !launched }
    override func supportLost(_ c: Cat) { if !launched { super.supportLost(c) } }
    override func onPet(_ c: Cat) -> Bool { false }

    override func begin(_ c: Cat) {
        c.blendRate = 16
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let toy = Den.shared.toy!
        guard toy.visible else { return false }
        if !launched {
            let dx = toy.p.x - c.pos.x
            if abs(dx) > 4 { c.facing = dx > 0 ? 1 : -1 }
            c.target = .crouch(wiggle: t > crouch * 0.3 ? sin(t * 18) : 0)
            c.look(at: toy.p)
            if toy.state == .caught { return false }
            if t < crouch { return true }
            guard let s = c.currentSurface else { return false }
            launch(c, s, toy)
        }
        let tau = t - tLaunch
        let k = min(1, tau / T)
        c.pos.x = p0.x + (p1.x - p0.x) * k
        c.pos.y = p0.y + vy0 * tau + 0.5 * g * tau * tau
        c.target = .leap(t: min(0.45, k))
        c.blendRate = 22
        let paw = c.pawWorld
        if !touched, toy.state != .caught, hypot(paw.x - toy.p.x, paw.y - toy.p.y) < toy.r + 15 * c.scale {
            touched = true
            // Cats miss plenty: sometimes the paw just bats it away.
            let odds: CGFloat = toy.state == .held ? 0.45 : (toy.speed > 150 ? 0.5 : 0.65)
            if !chance(odds) {
                if toy.state == .held {
                    c.effects.say("!", at: CGPoint(x: c.facing * 30, y: 30), color: .systemPink, life: 0.6)
                } else {
                    toy.toss(CGPoint(x: c.facing * .random(in: 220...420), y: -.random(in: 150...350)))
                }
                return true
            }
            toy.caught(by: c)
            c.spawn(.sparkle, dx: c.facing * 14, dy: -6, v: CGPoint(x: 0, y: 24), life: 0.6)
            c.interrupt(with: [Fall(vx: 0, vy: max(0, (vy0 + g * tau) * 0.3)), PlayWithToy()])
            return true
        }
        if tau >= T {
            c.pos = p1   // don't overshoot below the ledge
            c.queue.insert(Fall(vx: (p1.x - p0.x) / T * 0.2, vy: vy0 + g * tau), at: 0)
            return false
        }
        return true
    }

    private func launch(_ c: Cat, _ s: Surface, _ toy: Toy) {
        launched = true
        tLaunch = t
        p0 = c.pos
        let lead = CGPoint(x: max(-400, min(400, toy.v.x)) * 0.2, y: max(-400, min(400, toy.v.y)) * 0.2)
        var target = CGPoint(x: toy.p.x + lead.x - c.facing * 30 * c.scale, y: toy.p.y + lead.y + 17 * c.scale)
        target.y = max(s.y - 230 * c.scale, min(s.y, target.y))
        target.x = max(s.minX - 50, min(s.maxX + 50, target.x))
        p1 = target
        let apex = min(p0.y, p1.y) - (10 + 0.12 * abs(p1.x - p0.x)) * c.scale
        let t1 = sqrt(2 * max(1, p0.y - apex) / g)
        let t2 = sqrt(2 * max(1, p1.y - apex) / g)
        T = t1 + t2
        vy0 = -g * t1
        c.surface = nil
        c.attach = nil
        c.effects.dust(at: .zero, strength: 0.5)
    }
}

/// Caught it! Bunny-kick it, bat it about, then let it roll away.
final class PlayWithToy: Act {
    private let duration = CGFloat.random(in: 3...6)
    private var kicking = Bool.random()
    private var switchAt = CGFloat.random(in: 1.2...2)
    private var fxClock: CGFloat = 0.6

    override var status: String { "Got the yarn ball!" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        c.blendRate = 14
        c.lookAtCursor = false
        c.lastToyChase = c.time
        if !c.isHidden { c.depth = .top }   // playing happens in front of everything
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let toy = Den.shared.toy!
        guard toy.holder === c, toy.state == .caught else {
            // Somebody took it!
            c.queue.insert(Idle(.sit, 1), at: 0)
            return false
        }
        if t > switchAt {
            kicking.toggle()
            switchAt = t + .random(in: 1.2...2)
        }
        let center: CGPoint
        if kicking {
            c.target = .bunnyKick(t * 15)
            center = CGPoint(x: 24 + sin(t * 15) * 1.5, y: 15 + cos(t * 15) * 1.2)
        } else {
            let swipe = (sin(t * 7) + 1) / 2
            c.target = .bat(swipe)
            center = CGPoint(x: 33 + swipe * 7, y: 9 + abs(sin(t * 7)) * 7)
        }
        toy.hold(at: CGPoint(x: c.pos.x + c.facing * center.x * c.scale, y: c.pos.y - center.y * c.scale))
        fxClock -= dt
        if fxClock <= 0 {
            fxClock = .random(in: 0.8...1.4)
            c.spawn(chance(0.5) ? .sparkle : .heart, dx: .random(in: -12...12), dy: 10, v: CGPoint(x: 0, y: 22), life: 0.9)
        }
        if t > duration {
            toy.release(v: CGPoint(x: c.facing * .random(in: 160...300), y: -.random(in: 200...380)))
            c.energy = max(0, c.energy - 0.04)
            let again = c.energy > 0.4 && chance(0.35)
            c.queue.insert(contentsOf: again ? [Idle(.sit, 0.6), ChaseToy()] : [Idle(.sit, 1.2), Groom(2.5)], at: 0)
            if !again { c.settleDepth() }
            return false
        }
        return true
    }

    override func end(_ c: Cat) {
        let toy = Den.shared.toy!
        if toy.holder === c { toy.release(v: CGPoint(x: c.facing * 120, y: -220)) }
    }
}
