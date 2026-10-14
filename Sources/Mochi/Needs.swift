import Foundation

// MARK: - Hunger, thirst and mood

extension Cat {
    var bowls: Bowls { Den.shared.bowls }

    var isHungry: Bool { hunger > 0.55 }
    var isThirsty: Bool { thirst > 0.5 }

    /// Hungry or thirsty, and the bowl it needs is empty.
    var isStarving: Bool {
        (hunger > 0.7 && bowls.food < 0.03) || (thirst > 0.7 && bowls.water < 0.03)
    }

    func tickNeeds(_ dt: CGFloat) {
        let k = Den.needsSpeed
        // A full stomach lasts ~25 minutes; thirst comes back a little sooner.
        let rate: CGFloat = isAsleep ? 0.5 : 1
        hunger = min(1, hunger + dt * k * rate / (25 * 60))
        thirst = min(1, thirst + dt * k * rate / (18 * 60))
        if isStarving {
            grumpy = min(1, grumpy + dt * k / 150)       // ~2.5 minutes of neglect to full fury
        } else if !isHungry && !isThirsty {
            grumpy = max(0, grumpy - dt / 120)
        }
    }

    /// A short line for the menu about what this cat needs.
    var needsNote: String? {
        if isStarving { return bowls.food < 0.03 && hunger > 0.7 ? "hungry and grumpy, the food bowl is empty!" : "thirsty and grumpy, the water bowl is empty!" }
        if grumpy > 0.4 { return "still grumpy" }
        if hunger > 0.7 && bowls.food < 0.03 { return "hungry, the food bowl is empty" }
        if thirst > 0.7 && bowls.water < 0.03 { return "thirsty, the water bowl is empty" }
        return nil
    }

    /// Head to the bowls to eat or drink (or to complain if it's empty). Returns false if it can't get there.
    @discardableResult
    func goToBowls(drink: Bool) -> Bool {
        let b = bowls, bs = b.surface
        let center = (bs.minX + bs.maxX) / 2
        let side: CGFloat = pos.x < center ? -1 : 1
        let spot = b.spot(drink: drink, side: side)
        if surface == .bowls {
            queue = [Walk(to: spot, speed: 50), Eat(drink: drink)]
            return true
        }
        guard let s = currentSurface else { return false }
        if let bi = world.screenIndex(of: .bowls), bi != screenIndex {
            // The bowls are on another display.
            return travel(to: bi, then: [GoToBowlsLater(drink: drink)])
        }
        if s.ref == .box {
            queue = [LeaveBox(dir: spot > pos.x ? 1 : -1), Jump(to: .bowls, x: spot, crouch: 0.4, canSlip: false), Eat(drink: drink)]
            return true
        }
        let dx = abs(spot - pos.x), rise = s.y - bs.y
        let onFloor: Bool = { if case .floor = s.ref { return true } else { return false } }()
        if (dx < 700 && rise < 600) || onFloor {
            // Take off where nothing covers the cat, so it doesn't pop through a window.
            func clear(_ x: CGFloat) -> Bool { bs.z <= z || !world.covered(CGPoint(x: x, y: s.y - 20), above: z, upTo: bs.z) }
            var launch = s.clamp(spot + side * .random(in: 60...130))
            if !clear(launch), let x = stride(from: 40, through: 900, by: 40).lazy
                .flatMap({ d in [spot - CGFloat(d), spot + CGFloat(d)] })
                .first(where: { $0 > s.minX && $0 < s.maxX && clear($0) }) {
                launch = x
            }
            queue = [Walk(to: launch, speed: 75), Jump(to: .bowls, x: spot, crouch: 0.45, canSlip: false), Eat(drink: drink)]
            return true
        }
        if case .window = s.ref {
            let dir: CGFloat = spot < pos.x ? -1 : 1
            queue = [Walk(to: dir < 0 ? s.minX : s.maxX, speed: 70), HopOff(dir: dir), GoToBowlsLater(drink: drink)]
            return true
        }
        return false
    }

    /// Something to do while in a bad mood.
    func planGrump() {
        let starving = isStarving
        let choice = pick([
            (0, 3.0),                                   // sulk with its back to you
            (1, 2.0),                                   // sit and glare
            (2, starving && time - lastComplain > 25 ? 3.0 : 0),   // go yell at the empty bowl
        ]) ?? 0
        switch choice {
        case 0: queue = [Sulk(.random(in: 6...12))]
        case 1: queue = [Idle(.sit, .random(in: 4...8))]
        default:
            lastComplain = time
            if !goToBowls(drink: thirst > 0.7 && bowls.water < 0.03) { queue = [Sulk(6)] }
        }
    }

    /// Grumpy cats hiss when the pointer comes too close.
    func considerMood() {
        guard grumpy > 0.6, time - lastHiss > 7, let a = action, a is Idle || a is Sulk || a is Walk,
              currentSurface != nil else { return }
        let m = Coords.mouse, h = headWorld
        guard hypot(m.x - h.x, m.y - h.y) < 75 * scale else { return }
        lastHiss = time
        interrupt(with: [Hiss(at: m), Sulk(.random(in: 4...8))])
    }
}

final class GoToBowlsLater: Act {
    let drink: Bool
    init(drink: Bool) { self.drink = drink }
    override func begin(_ c: Cat) { if !c.goToBowls(drink: drink) { c.queue = [] } }
}

// MARK: - Eating and drinking

final class Eat: Act {
    let drink: Bool
    private let duration = CGFloat.random(in: 4...6.5)
    private var fxClock: CGFloat = 0.4
    private var bowlX: CGFloat = 0
    init(drink: Bool) { self.drink = drink }

    override var status: String { drink ? "Drinking water" : "Eating  nom nom" }
    override var grounded: Bool { true }
    override var showsMood: Bool { false }

    override func begin(_ c: Cat) {
        c.blendRate = 10
        c.lookAtCursor = false
        let b = c.bowls
        bowlX = (b.spot(drink: drink, side: -1) + b.spot(drink: drink, side: 1)) / 2
        if abs(bowlX - c.pos.x) > 2 { c.facing = bowlX > c.pos.x ? 1 : -1 }
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        guard c.surface == .bowls else { return false }
        let b = c.bowls
        if b.amount(drink: drink) < 0.005 {
            // Empty! Make a fuss about it.
            c.queue.insert(Complain(drink: drink), at: 0)
            return false
        }
        if t < 0.25 { c.target = .stand(); return true }
        let chew = (sin(t * (drink ? 11 : 8)) + 1) / 2
        c.target = .eat(chew: chew, drinking: drink)
        let mouthful: CGFloat = drink ? 0.12 : 0.18
        let got = b.consume(mouthful / duration * dt, drink: drink)
        if drink { c.thirst = max(0, c.thirst - got / mouthful * 0.8) } else { c.hunger = max(0, c.hunger - got / mouthful * 0.7) }

        fxClock -= dt
        if fxClock <= 0 {
            fxClock = .random(in: 0.5...0.9)
            let mouth = CGPoint(x: c.facing * 30, y: 6)
            for _ in 0..<2 {
                c.effects.spawn(drink ? .drop : .crumb, at: mouth,
                                v: CGPoint(x: .random(in: -25...25), y: .random(in: 30...70)), life: 0.5)
            }
            if !drink && chance(0.4) { c.effects.say("nom", at: CGPoint(x: c.facing * 18, y: 26), color: .systemBrown, life: 1) }
        }
        if t > duration {
            c.grumpy = max(0, c.grumpy - 0.4)
            c.effects.hearts(at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 14), count: 1)
            c.queue.insert(contentsOf: [Idle(.sit, 0.8), Groom(.random(in: 2...3.5))], at: 0)
            return false
        }
        return true
    }
}

/// Sitting by an empty bowl, yelling about it.
final class Complain: Act {
    let drink: Bool
    private let duration = CGFloat.random(in: 5...8)
    private var meowClock: CGFloat = 0.3
    init(drink: Bool) { self.drink = drink }

    override var status: String { drink ? "Yelling at the empty water bowl" : "Yelling at the empty food bowl" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 10
        c.lookAtCursor = true
        c.lastComplain = c.time
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        if c.bowls.amount(drink: drink) > 0.05 {
            // Refilled!
            c.effects.say("!", at: CGPoint(x: c.headLocal.x, y: c.headLocal.y + 18), color: .systemPink)
            c.queue.insert(Eat(drink: drink), at: 0)
            return false
        }
        meowClock -= dt
        let mouth = max(0, 1 - (1.6 - meowClock) * 3)
        c.target = .sitFront()
        c.target.mouthOpen = 0.75 * mouth
        c.target.eyes = mouth > 0.3 ? .happy : .open
        if meowClock <= 0 {
            meowClock = 1.6
            let angry = c.grumpy > 0.5
            c.effects.say(angry ? "MEOW!!" : "mew!", at: CGPoint(x: c.headLocal.x + 10, y: c.headLocal.y + 20),
                          color: angry ? .systemRed : .systemBrown)
            if angry { c.spawn(.anger, dx: 14, dy: 14, v: CGPoint(x: 4, y: 12), life: 0.9) }
        }
        return t < duration
    }
}

// MARK: - Bad moods

/// Back turned, tail thumping. Occasionally glances over its shoulder to check you've noticed.
final class Sulk: Act {
    let duration: CGFloat
    private var glanceAt = CGFloat.random(in: 2...4)
    private var angerClock: CGFloat = 1
    init(_ duration: CGFloat) { self.duration = duration }

    override var status: String { "Sulking (the bowls need filling)" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        c.blendRate = 9
        c.lookAtCursor = false
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let glancing = t > glanceAt && t < glanceAt + 0.9
        if t > glanceAt + 0.9 { glanceAt = t + .random(in: 2.5...4.5) }
        if glancing {
            c.target = Pose.sitFront().grumpy(1)
            c.lookAtCursor = true
        } else {
            c.target = .sulk()
            c.lookAtCursor = false
        }
        angerClock -= dt
        if angerClock <= 0 {
            angerClock = .random(in: 2.5...4)
            c.spawn(.anger, dx: 12, dy: 12, v: CGPoint(x: 4, y: 10), life: 1)
        }
        return t < duration
    }
}

/// Puffed up, back arched, hissing at something.
final class Hiss: Act {
    let at: CGPoint
    init(at: CGPoint) { self.at = at }
    override var status: String { "Hissing!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        if abs(at.x - c.pos.x) > 3 { c.facing = at.x > c.pos.x ? 1 : -1 }
        c.blendRate = 18
        c.lookAtCursor = false
        c.effects.say("hss!", at: CGPoint(x: c.facing * 30, y: 44), color: .systemRed, life: 1.1)
        c.spawn(.anger, dx: c.facing * -6, dy: 16, v: CGPoint(x: 0, y: 14), life: 1)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        c.target = .hiss()
        c.target.lookX = 1
        return t < 1.4
    }
}

/// Swipes at the hand that dares to pet it while the bowls are empty.
final class Swat: Act {
    override var status: String { "Not in the mood!" }
    override var grounded: Bool { true }

    override func begin(_ c: Cat) {
        let m = Coords.mouse
        if abs(m.x - c.pos.x) > 3 { c.facing = m.x > c.pos.x ? 1 : -1 }
        c.blendRate = 22
        c.lookAtCursor = false
        c.effects.say("hss!", at: CGPoint(x: c.facing * 28, y: 46), color: .systemRed, life: 1)
        c.spawn(.anger, dx: 0, dy: 16, v: CGPoint(x: 0, y: 14), life: 1)
    }

    override func step(_ c: Cat, _ dt: CGFloat) -> Bool {
        let swipe = max(0, sin(t * 16))
        c.target = Pose.bat(swipe).grumpy(1)
        c.target.footFN.y += 12 * swipe
        c.target.mouthOpen = 0.6
        return t < 0.8
    }
}
