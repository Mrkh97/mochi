import Foundation

/// One thing a cat does. `step` returns false when finished.
class Act {
    var t: CGFloat = 0
    var status: String { "" }
    /// Standing on a surface (so a shaken window can knock it off).
    var grounded: Bool { false }
    /// Show a grumpy face if the cat is in a bad mood.
    var showsMood: Bool { true }
    func begin(_ c: Cat) {}
    func step(_ c: Cat, _ dt: CGFloat) -> Bool { false }
    func end(_ c: Cat) {}
    /// The window under the cat vanished.
    func supportLost(_ c: Cat) { c.interrupt(with: [Fall(startled: true)]) }
    /// Clicked. Return true if handled.
    func onPet(_ c: Cat) -> Bool {
        guard grounded || c.surface == .box else { return false }
        c.interrupt(with: [Petted()])
        return true
    }
}

func ease(_ x: CGFloat) -> CGFloat { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }

// MARK: - Idle

final class Idle: Act {
    enum Style { case stand, sit, sitFront, loaf }
    let style: Style
    let duration: CGFloat
    private var hover: CGFloat = 0
    private var slowBlink: CGFloat = -1
    private var glance: CGFloat = 0

    init(_ style: Style, _ duration: CGFloat) {
        self.style = style
        self.duration = duration
    }

    override var status: String {
        switch style {
        case .loaf: return "Loafing"
        case .sitFront: return "Watching you"
        default: return "Sitting pretty"
        }
    }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 7
        c.lookAtCursor = true
        glance = .random(in: 0...6)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        switch style {
        case .stand: c.target = .stand()
        case .sit: c.target = .sit()
        case .sitFront: c.target = .sitFront()
        case .loaf: c.target = .loaf()
        }
        // Now and then look at the viewer.
        if style == .sit || style == .loaf {
            c.target.headTurn = 0.55 + 0.45 * sin(t * 0.7 + glance)
        }
        // Hovering the pointer near its face earns a slow blink (a cat "I love you").
        let m = Coords.mouse, h = c.headWorld
        if hypot(m.x - h.x, m.y - h.y) < 70 * c.scale { hover += dt } else { hover = 0 }
        if hover > 1.2 && slowBlink < 0 { slowBlink = 0; hover = -3 }
        if slowBlink >= 0 {
            slowBlink += dt
            if slowBlink < 1.4 { c.target.eyes = .happy; c.target.blush = 0.9 } else { slowBlink = -1 }
        }
        return t < duration
    }
}

// MARK: - Walk

final class Walk: Act {
    var toX: CGFloat
    let speed: CGFloat
    let zoom: Bool
    private var phase: CGFloat = 0
    private var started = false

    init(to x: CGFloat, speed: CGFloat = 55, zoom: Bool = false) {
        toX = x
        self.speed = speed
        self.zoom = zoom
    }

    override var status: String { zoom ? "Zoomies!!" : "Strolling" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 14
        c.lookAtCursor = true
        if abs(toX - c.pos.x) > 2 { c.facing = toX > c.pos.x ? 1 : -1 }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard let s = c.currentSurface else { return false }
        let goal = s.clamp(toX)
        let dx = goal - c.pos.x
        if abs(dx) < 1 { c.target = .stand(); return false }
        c.facing = dx > 0 ? 1 : -1
        // Wait for the turn-around to finish before setting off.
        if t < 0.14 && !started { c.target = .stand(); return true }
        started = true
        let accel = min(1, t * 3)
        let move = min(abs(dx), speed * accel * c.activityBoost * dt)
        c.pos.x += c.facing * move
        let v = move / max(dt, 0.001)
        phase += move / (8 * c.scale)
        c.target = .walk(phase: phase, speed: v / c.scale)
        if zoom {
            c.target.earPerk = 0.25
            c.target.eyes = .open
            c.target.eyeOpen = 1.15
            c.target.tailAngle = 2.6
        }
        return true
    }
}

// MARK: - Groom

final class Groom: Act {
    let duration: CGFloat
    private var washing = false
    private var switchAt: CGFloat = 1.5

    init(_ duration: CGFloat) { self.duration = duration }
    override var status: String { "Grooming" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 9
        c.lookAtCursor = false
        switchAt = .random(in: 1.2...2.4)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        if t > switchAt {
            washing.toggle()
            switchAt = t + (washing ? .random(in: 1.0...1.8) : .random(in: 1.4...2.6))
        }
        let lick = (sin(t * (washing ? 6.5 : 13)) + 1) / 2
        c.target = .groom(lick: lick, wash: washing ? 1 : 0)
        if t >= duration {
            c.spawn(.sparkle, dx: 14, dy: 10, v: CGPoint(x: 6, y: 18), life: 0.8)
            return false
        }
        return true
    }
}

// MARK: - Stretch

final class Stretch: Act {
    override var status: String { "Stretching" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 6
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let yawn = ease((t - 0.7) / 0.5) * (1 - ease((t - 1.9) / 0.4))
        c.target = .stretch(yawn: yawn)
        return t < 2.6
    }
}

// MARK: - Land (squash after touching down)

final class Land: Act {
    let impact: CGFloat
    init(_ impact: CGFloat) { self.impact = min(1.5, impact) }
    override var status: String { "Sticking the landing" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 16
        c.pose.squashY = 1 - 0.28 * impact
        c.pose.squashX = 1 + 0.18 * impact
        c.effects.dust(at: .zero, strength: 0.6 + impact * 0.5)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        if c.surface == .box { return false }
        c.target = .stand()
        c.target.earPerk = 0.8
        return t < 0.22 + 0.15 * impact
    }
}

// MARK: - Sleep

final class Sleep: Act {
    let duration: CGFloat
    private var phase = 0          // 0 knead, 1 settle, 2 asleep, 3 waking
    private var phaseT: CGFloat = 0
    private var zClock: CGFloat = 0
    private var purrUntil: CGFloat = -1
    private var inBox = false

    init(_ duration: CGFloat) { self.duration = duration }
    override var status: String { phase == 0 ? "Making biscuits" : (phase == 3 ? "Waking up" : "Sleeping  z z z") }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        inBox = c.surface == .box
        c.lookAtCursor = false
        c.allowBlink = false
        phase = inBox ? 1 : 0
    }

    override func end(_ c: Cat) { c.allowBlink = true }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        phaseT += dt
        c.energy = min(1, c.energy + dt / 75)
        let breath = (sin(t * 1.6) + 1) / 2
        switch phase {
        case 0: // knead the spot first
            c.blendRate = 9
            c.target = .loaf()
            c.target.tuck = 0
            c.target.body.y = 15
            c.target.head = CGPoint(x: 20, y: 31)
            c.target.footFN = CGPoint(x: 14, y: max(0, sin(phaseT * 9)) * 5)
            c.target.footFF = CGPoint(x: 17, y: max(0, -sin(phaseT * 9)) * 5)
            c.target.eyes = .happy
            c.target.purr = 1
            if phaseT > 2.2 { phase = 1; phaseT = 0; c.facing = -c.facing }
        case 1:
            c.blendRate = 3.5
            c.target = sleepPose(c, breath)
            c.target.eyes = .sleep
            if phaseT > 1.4 { phase = 2; phaseT = 0 }
        case 2:
            c.blendRate = 3
            c.target = sleepPose(c, breath)
            zClock -= dt
            if zClock <= 0 {
                zClock = 1.5
                c.spawn(.z, dx: 10, dy: 12, v: CGPoint(x: 9, y: 16), life: 2.4)
            }
            // Purr when snuggled up with a sleeping friend.
            let snuggled = Den.shared.others(than: c).contains {
                $0.isAsleep && $0.surface == c.surface && abs($0.pos.x - c.pos.x) < 70 * c.scale
            }
            if t > purrUntil && !snuggled { c.target.purr = 0 } else { c.target.purr = 1; c.target.blush = 1 }
            if snuggled && Int(t * 10) % 70 == 0 {
                c.effects.hearts(at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 10), count: 1)
            }
            if t > duration { phase = 3; phaseT = 0 }
        default:
            c.blendRate = 5
            c.target = sleepPose(c, breath)
            c.target.eyes = phaseT > 0.5 ? .open : .sleep
            c.target.eyeOpen = 0.4 + phaseT * 0.5
            c.target.earPerk = 1
            if phaseT > 1.1 {
                if !inBox { c.queue.insert(Stretch(), at: 0) }
                return false
            }
        }
        return true
    }

    private func sleepPose(_ c: Cat, _ breath: CGFloat) -> Pose {
        if inBox {
            var p = Pose.peek(rise: 0.86 + breath * 0.02)
            p.eyes = .sleep
            p.headTilt = 0.12
            p.blush = 0.8
            p.earPerk = 0.75
            return p
        }
        return .sleep(breath: breath)
    }

    override func onPet(_ c: Cat) -> Bool {
        purrUntil = t + 2
        c.effects.hearts(at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 12), count: 2)
        c.spawn(.note, dx: -8, dy: 14, v: CGPoint(x: -8, y: 22), life: 1.4)
        if Int.random(in: 0..<4) == 0 && phase == 2 { phase = 3; phaseT = 0 }
        return true
    }
}

// MARK: - Petted

final class Petted: Act {
    private var until: CGFloat = 2.6
    private var noteClock: CGFloat = 0.4
    private var inBox = false

    override var status: String { "Purring  ♥" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        inBox = c.surface == .box
        c.blendRate = 10
        c.lookAtCursor = false
        c.effects.hearts(at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 16))
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = inBox ? .peek(rise: 1) : .sitFront()
        c.target.eyes = .happy
        c.target.blush = 1.2
        c.target.purr = 1
        c.target.earPerk = 0.85
        c.target.headTilt = sin(t * 2.2) * 0.12
        c.target.tailSway = 0.3
        noteClock -= dt
        if noteClock <= 0 {
            noteClock = 0.9
            c.spawn(.note, dx: .random(in: -12...12), dy: 16, v: CGPoint(x: .random(in: -10...10), y: 24), life: 1.3)
        }
        return t < until
    }

    override func onPet(_ c: Cat) -> Bool {
        until = max(until, t + 1.6)
        c.effects.hearts(at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 16), count: 2)
        return true
    }
}

// MARK: - The box

final class BoxIdle: Act {
    let duration: CGFloat
    private var duck: CGFloat = -1
    init(_ duration: CGFloat) { self.duration = duration }
    override var status: String { "In the box (if it fits, it sits)" }

    override func begin(_ c: Cat) {
        c.blendRate = 8
        c.lookAtCursor = true
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = .peek(rise: 1)
        c.target.headTilt = sin(t * 0.8) * 0.1
        // Peekaboo: duck down into the box, then pop back up.
        if duck < 0 && Int.random(in: 0..<900) == 0 { duck = 0 }
        if duck >= 0 {
            duck += dt
            c.target = .peek(rise: duck < 1.2 ? 0.25 : 1)
            if duck > 1.25 && duck < 1.3 { c.spawn(.sparkle, dx: 16, dy: 14, v: CGPoint(x: 10, y: 20), life: 0.7) }
            if duck > 1.8 { duck = -1 }
        }
        return t < duration
    }
}

/// Stand up on the rim, ready to hop out.
final class LeaveBox: Act {
    let dir: CGFloat
    init(dir: CGFloat) { self.dir = dir }
    override var status: String { "Climbing out of the box" }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.blendRate = 12
        if t < 0.25 {
            c.target = .peek(rise: 1)
            c.target.headTilt = 0
            return true
        }
        if c.depth != .onBox {
            c.depth = .onBox
            c.facing = dir
            c.target = .stand()
            c.target.squashY = 1.1
            c.snapTurn()
        }
        c.target = .stand()
        return t < 0.5
    }
}
