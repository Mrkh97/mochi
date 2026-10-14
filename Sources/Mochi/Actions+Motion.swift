import AppKit

// MARK: - Jump

/// Crouch, wiggle that bum, and leap onto a surface.
final class Jump: Act {
    let dest: SurfaceRef
    var landX: CGFloat
    let crouch: CGFloat
    let canSlip: Bool
    private var launched = false
    private var p0 = CGPoint.zero
    private var y1Start: CGFloat = 0
    private var vy0: CGFloat = 0
    private var T: CGFloat = 0.5
    private var tLaunch: CGFloat = 0
    private let g: CGFloat = 2600

    init(to dest: SurfaceRef, x: CGFloat, crouch: CGFloat = .random(in: 0.45...0.95), canSlip: Bool = true) {
        self.dest = dest
        landX = x
        self.crouch = crouch
        self.canSlip = canSlip
    }

    override var status: String { launched ? "Wheee!" : "Wiggling… about to jump" }
    override var grounded: Bool { !launched }

    override func begin(_ c: Cat) {
        if abs(landX - c.pos.x) > 3 { c.facing = landX > c.pos.x ? 1 : -1 }
        c.lookAtCursor = false
        c.blendRate = 12
    }

    override func supportLost(_ c: Cat) {
        if !launched { super.supportLost(c) }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard let s = c.world.surface(dest) else {
            if launched { c.interrupt(with: [Fall(vx: (landX - p0.x) / T, vy: 0)]); return true }
            return false
        }
        if !launched {
            c.target = .crouch(wiggle: t > crouch * 0.35 ? sin(t * 17) : 0)
            c.target.lookY = s.y < c.pos.y ? 0.6 : -0.4
            if t < crouch { return true }
            launch(c, s)
        }
        let tau = t - tLaunch
        let k = min(1, tau / T)
        landX = s.clamp(landX)
        c.pos.x = p0.x + (landX - p0.x) * k
        c.pos.y = p0.y + vy0 * tau + 0.5 * g * tau * tau + (s.y - y1Start) * k
        c.target = .leap(t: k)
        c.blendRate = 20
        if tau >= T { touchDown(c, s); return false }
        return true
    }

    private func launch(_ c: Cat, _ s: Surface) {
        launched = true
        tLaunch = t
        p0 = c.pos
        y1Start = s.y
        let dx = abs(landX - p0.x)
        let apex = min(p0.y, s.y) - (16 + 0.16 * dx + (s.y < p0.y ? 14 : 4)) * max(0.8, c.scale)
        let t1 = sqrt(2 * max(1, p0.y - apex) / g)
        let t2 = sqrt(2 * max(1, s.y - apex) / g)
        T = t1 + t2
        vy0 = -g * t1
        // Moving toward the viewer happens at take-off, away from the viewer on landing.
        let destDepth = c.depthAfterLanding(on: s)
        if c.world.z(of: destDepth) > c.z { c.depth = destDepth }
        c.surface = nil
        c.attach = nil
        c.effects.dust(at: .zero, strength: 0.7)
    }

    private func touchDown(_ c: Cat, _ s: Surface) {
        let drop = c.pos.y - p0.y
        let dist = abs(c.pos.x - p0.x)
        c.stand(on: s, x: landX)
        c.depth = c.depthAfterLanding(on: s)
        if s.ref == .box {
            c.queue.insert(BoxIdle(.random(in: 6...14)), at: 0)
            c.pose = .peek(rise: 0.4)
            c.target = .peek(rise: 1)
            c.snapTurn()
            return
        }
        let impact = min(1.3, 0.35 + max(0, drop) / 400 + dist / 900)
        if case .window(let id) = s.ref, let w = c.world.window(id) {
            let risky = dist > 170 || drop > 140
            if canSlip && CGFloat.random(in: 0...1) < (Cat.testMode ? 0.5 : (risky ? 0.22 : 0.06)) {
                c.queue.insert(Slip(cause: .landing), at: 0)
                return
            }
            if impact > 0.7 { Nudger.shared.jiggle(w, amplitude: 3) }
        }
        c.queue.insert(Land(impact), at: 0)
    }
}

// MARK: - Fall

final class Fall: Act {
    var vx: CGFloat
    var vy: CGFloat
    let startled: Bool
    /// Dropping through the bottom of this display onto the one below: nothing on it catches the cat.
    let through: Int?
    private var arrived = false
    private let g: CGFloat = 2600

    init(vx: CGFloat = 0, vy: CGFloat = 0, startled: Bool = false, through: Int? = nil) {
        self.vx = vx
        self.vy = vy
        self.startled = startled
        self.through = through
    }
    convenience init(startled: Bool) { self.init(vx: 0, vy: 0, startled: startled) }

    override var status: String { startled ? "Aaaa!" : (through != nil ? "Dropping down to the other screen" : "Hopping down") }
    override func supportLost(_ c: Cat) {}

    override func begin(_ c: Cat) {
        c.world.refreshIfStale(0.1)
        c.surface = nil
        c.attach = nil
        c.lookAtCursor = false
        c.blendRate = 16
        if startled { c.spawn(.exclaim, dx: 14, dy: 18, v: CGPoint(x: 0, y: 20), life: 0.7) }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        vy = min(2200, vy + g * dt)
        vx *= 1 - 0.8 * dt
        let si = c.screenIndex
        let v = c.world.screens[si].visible, fr = c.world.screens[si].frame
        var x = c.pos.x + vx * dt
        // Displays that touch are one big playground: only bounce off edges with nothing beyond them.
        if x < v.minX + 20 && !c.world.onAnyScreen(CGPoint(x: fr.minX - 2, y: c.pos.y)) { x = v.minX + 20; vx = abs(vx) * 0.4 }
        if x > v.maxX - 20 && !c.world.onAnyScreen(CGPoint(x: fr.maxX + 2, y: c.pos.y)) { x = v.maxX - 20; vx = -abs(vx) * 0.4 }
        if abs(vx) > 20 { c.facing = vx > 0 ? 1 : -1 }
        let y0 = c.pos.y, y1 = c.pos.y + vy * dt
        if let p = through {
            if si == p && y0 < fr.maxY + 300 {
                // Still on its way out through the bottom of the display above.
                c.pos = CGPoint(x: x, y: y1)
                c.target = .leap(t: 0.85)
                return true
            }
            if !arrived {
                // Coming in at the top of the new display (behind its menu bar): drop in front of its windows.
                arrived = true
                c.depth = .top
            }
        }
        // Nothing falls through the floor, even if a frame overshot it.
        let floor = c.world.surface(.floor(si))
        let floorHit = floor.flatMap { f in y1 >= f.y ? f : nil }
        if vy > 0, let s = c.world.landing(x: x, fromY: min(y0, floor?.y ?? y0), toY: max(y1, y0 + 0.5), z: c.z, screen: si) ?? floorHit {
            c.pos.x = x
            c.stand(on: s, x: s.ref == .box ? s.clamp(x) : x)
            c.depth = c.depthAfterLanding(on: s)
            if s.ref == .box {
                c.queue.insert(BoxIdle(.random(in: 6...12)), at: 0)
                c.target = .peek(rise: 1)
                c.snapTurn()
                return false
            }
            let impact = min(1.4, vy / 1400)
            c.target = .stand()
            c.snapTurn()
            c.queue.insert(Land(impact + 0.2), at: 0)
            if startled {
                // Pretend that was on purpose.
                c.queue.insert(contentsOf: [Idle(.sit, 0.8), Groom(.random(in: 2.5...4))], at: 1)
                c.spawn(.sweat, dx: 16, dy: 14, v: CGPoint(x: 10, y: 10), life: 1)
            }
            if case .window(let id) = s.ref, let w = c.world.window(id), impact > 0.6 {
                Nudger.shared.jiggle(w, amplitude: 4)
            }
            return false
        }
        c.pos = CGPoint(x: x, y: y1)
        c.target = startled ? .fall() : .leap(t: 0.85)
        return true
    }
}

// MARK: - Hop off a ledge

final class HopOff: Act {
    let dir: CGFloat
    let behind: Bool
    init(dir: CGFloat, behind: Bool = false) {
        self.dir = dir
        self.behind = behind
    }
    override var status: String { behind ? "Sneaking behind a window" : "Hopping down" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.facing = dir
        c.blendRate = 12
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = .crouch(wiggle: 0)
        if t < 0.3 { return true }
        if behind, case .window(let id)? = c.surface {
            // Slip behind the window we were sitting on.
            let ws = c.world.windows
            if let i = ws.firstIndex(where: { $0.id == id }) {
                c.depth = i + 1 < ws.count ? .above(ws[i + 1].id) : .desktop
            }
            c.interrupt(with: [Fall(vx: dir * 40, vy: -420)] + c.queue)
        } else {
            // Keep whatever was planned for after the hop (going home, the bowls, another display…).
            c.interrupt(with: [Fall(vx: dir * 170, vy: -360)] + c.queue)
        }
        return true
    }
}

// MARK: - Climb behind a window, peek over the top, pull up

final class Climb: Act {
    let win: CGWindowID
    private var stage = 0          // 0 rear up, 1 climb, 2 peek, 3 pull up, 4 retreat
    private var stageT: CGFloat = 0
    private var peekFor: CGFloat = 2
    private let willPullUp = CGFloat.random(in: 0...1) < 0.82
    private var lookDir: CGFloat = 1

    init(_ win: CGWindowID) { self.win = win }
    override var status: String { stage <= 1 ? "Climbing up behind a window" : (stage == 2 ? "Peeking at you" : "Pulling up") }

    override func begin(_ c: Cat) {
        c.surface = nil
        c.attach = .window(win)
        c.lookAtCursor = false
        c.blendRate = 12
        c.target = .climb(phase: 0)
        c.pos.y -= 55 * c.scale   // origin moves from the feet up to the front paws
        c.snapTurn()
        peekFor = .random(in: 1.4...3)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard let w = c.world.window(win), let s = c.world.surface(.window(win)) else {
            c.interrupt(with: [Fall(startled: true)])
            return true
        }
        stageT += dt
        let top = w.frame.minY
        if stage < 3 && Double(w.z) < c.z {
            // The window got shuffled behind the cat; climbing its back no longer makes sense.
            c.interrupt(with: [Fall()])
            return true
        }
        switch stage {
        case 0:
            c.target = .climb(phase: 0)
            if stageT > 0.2 { stage = 1; stageT = 0 }
        case 1:
            c.pos.y -= (170 + min(200, (c.pos.y - top) * 0.4)) * c.scale * dt
            c.target = .climb(phase: t * 10)
            if c.pos.y <= top + 34 * c.scale { stage = 2; stageT = 0; c.pos.y = top }
        case 2:
            c.pos.y = top
            c.pos.x = s.clamp(c.pos.x)
            let rise = ease(stageT / 0.5) * 0.62 + ease((stageT - peekFor + 0.6) / 0.4) * 0.38
            c.target = .peek(rise: rise)
            if stageT > 0.6 && Int.random(in: 0..<70) == 0 { lookDir = -lookDir }
            c.target.lookX = lookDir
            c.target.headTilt = lookDir * 0.08
            c.lookAtCursor = stageT > 1.2
            if stageT > peekFor { stage = willPullUp ? 3 : 4; stageT = 0 }
        case 3:
            c.pos.y = top
            c.target = .hang(kick: sin(stageT * 18) * 0.6, effort: ease(stageT / 0.3))
            c.target.eyes = .open
            c.target.mouthOpen = 0
            if stageT > 0.32 {
                c.facing = Bool.random() ? 1 : -1
                c.stand(on: s, x: c.pos.x)
                c.depth = .above(win)
                c.target = .stand()
                c.snapTurn()
                c.queue.insert(Land(0.6), at: 0)
                return false
            }
        default:
            c.pos.y = top
            c.target = .peek(rise: 0.62 * (1 - ease(stageT / 0.35)))
            if stageT > 0.4 {
                c.pos.y = top + 50 * c.scale
                c.interrupt(with: [Fall()])
                return true
            }
        }
        return true
    }
}

// MARK: - Slip, catch the edge, scramble back up (or not)

final class Slip: Act {
    enum Cause { case landing, shaken, clumsy }
    let cause: Cause
    private var stage = 0
    private var stageT: CGFloat = 0
    private var hold: CGFloat = 2
    private let makesIt = CGFloat.random(in: 0...1) < 0.85
    private var sweatClock: CGFloat = 0.3

    init(cause: Cause) { self.cause = cause }
    override var status: String { stage == 1 ? "Hanging on for dear life!" : "Whoops!" }

    override func begin(_ c: Cat) {
        c.lookAtCursor = false
        c.blendRate = 18
        hold = .random(in: 1.3...2.6)
        c.spawn(.exclaim, dx: 14, dy: 18, v: CGPoint(x: 0, y: 24), life: 0.7)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        stageT += dt
        guard case .window(let id)? = c.attach, let w = c.world.window(id) else {
            c.interrupt(with: [Fall(startled: true)])
            return true
        }
        c.pos.y = w.frame.minY
        switch stage {
        case 0: // the paws go out from under it
            c.target = .stand()
            c.target.eyes = .wide
            c.target.earPerk = 0.2
            c.target.rotation = -0.35
            c.target.body.y = 12
            if stageT > 0.2 {
                stage = 1; stageT = 0
                c.target = .hang(kick: 0, effort: 0)
                c.snapTurn()
                c.pose.fBody.y += 10        // drops, then the arms catch it
                c.pose.squashY = 1.12
                Nudger.shared.jiggle(w, amplitude: 11)
                c.hostMovedAt = c.time
            }
        case 1: // dangle and scrabble
            let kick = sin(stageT * 12)
            c.target = .hang(kick: kick, effort: 0.25 + 0.2 * sin(stageT * 5))
            sweatClock -= dt
            if sweatClock <= 0 {
                sweatClock = 0.55
                c.spawn(.sweat, dx: .random(in: 12...18) * (Bool.random() ? 1 : -1), dy: 8, v: CGPoint(x: .random(in: -10...10), y: 14), life: 0.9)
            }
            if stageT > hold { stage = makesIt ? 2 : 3; stageT = 0 }
        case 2: // heave!
            c.target = .hang(kick: sin(stageT * 22), effort: ease(stageT / 0.35))
            if stageT > 0.38, let s = c.world.surface(.window(id)) {
                c.stand(on: s, x: s.clamp(c.pos.x))
                c.depth = .above(id)
                c.target = .stand()
                c.snapTurn()
                Nudger.shared.jiggle(w, amplitude: 4)
                c.hostMovedAt = c.time
                c.queue.insert(contentsOf: [Land(0.8), Idle(.sit, 0.7), Groom(.random(in: 3...5))], at: 0)
                return false
            }
        default: // can't hold on…
            c.target = .hang(kick: 0, effort: -0.3)
            c.target.eyes = .wide
            if stageT > 0.25 {
                c.pos.y += 62 * c.scale
                c.interrupt(with: [Fall(startled: true)])
                return true
            }
        }
        return true
    }
}

// MARK: - Carried by the scruff

final class Held: Act {
    private var vel = CGPoint.zero
    private var last: CGPoint?
    private var theta: CGFloat = 0
    private var omega: CGFloat = 0
    private var calm: CGFloat = 0

    override var status: String { "Being carried" }
    override func supportLost(_ c: Cat) {}
    override func onPet(_ c: Cat) -> Bool { false }

    override func begin(_ c: Cat) {
        c.surface = nil
        c.attach = nil
        c.depth = .top
        c.lookAtCursor = false
        c.blendRate = 18
        c.target = .held(kick: 0)
        c.target.eyes = .wide
        c.snapTurn()
        c.spawn(.exclaim, dx: 16, dy: 10, v: CGPoint(x: 0, y: 20), life: 0.6)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let m = Coords.mouse
        if let l = last, dt > 0 {
            let v = CGPoint(x: (m.x - l.x) / dt, y: (m.y - l.y) / dt)
            let ax = (v.x - vel.x) / dt
            vel = CGPoint(x: vel.x + (v.x - vel.x) * 0.35, y: vel.y + (v.y - vel.y) * 0.35)
            // Pendulum swing from the scruff.
            omega += (-26 * theta - 3.2 * omega - ax * 0.0009) * dt
            theta = max(-1, min(1, theta + omega * dt))
        }
        last = m
        c.pos = CGPoint(x: m.x, y: m.y + 4 * c.scale)
        let speed = hypot(vel.x, vel.y)
        calm = speed > 500 ? 0 : calm + dt
        c.target = .held(kick: speed > 500 ? sin(t * 16) : sin(t * 2) * 0.15)
        c.target.rotation = theta
        if calm < 0.5 || t < 0.5 { c.target.eyes = .wide; c.target.mouthOpen = 0.25 }
        return true
    }

    func release(_ c: Cat) {
        c.pos.y += 62 * c.scale   // origin moves from the scruff down to the feet
        let vx = max(-1100, min(1100, vel.x * 0.55))
        let vy = max(-900, min(600, vel.y * 0.45))
        c.interrupt(with: [Fall(vx: vx, vy: vy, startled: hypot(vx, vy) > 700)])
    }
}
